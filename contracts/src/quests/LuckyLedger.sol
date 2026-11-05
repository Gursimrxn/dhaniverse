// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IHousePool} from "../money/Links.sol";

/// @title LuckyLedger
/// @notice The weekly draw. Tickets are earned free (streak days, Rush runs, quests), never bought. Each week the keeper
///         commits to a secret seed, a Merkle root of everyone's ticket ranges, the ticket count and the prize. After
///         `revealDelayBlocks`, anyone reveals the seed; the winning ticket is
///         uint256(keccak256(abi.encode(seed, blockhash(commitBlock + 1)))) % ticketCount, so neither the keeper (who
///         didn't know that block hash) nor a block producer (who didn't know the seed) could pick it. The winner proves
///         their range and is paid from HousePool's SURPRISE bucket.
/// @dev Leaves are OpenZeppelin's standard double hash: keccak256(bytes.concat(keccak256(abi.encode(player, from, to)))),
///      with tickets [from, to) half-open. The seed hash is keccak256(abi.encode(seed)). The reveal must land within
///      256 blocks of the commit (the EVM forgets older block hashes); a missed draw can be voided by the admin, which
///      is public in DrawVoided. Spec: docs/architecture/spec.json, contract "LuckyLedger".
contract LuckyLedger is Ownable2Step, ReentrancyGuardTransient {
    /// @notice The EVM only remembers the last 256 block hashes.
    uint256 public constant BLOCKHASH_WINDOW = 256;

    IHousePool private immutable HOUSE_POOL;
    /// @notice Blocks to wait after a commit before the seed may be revealed (at least 1).
    uint256 public immutable revealDelayBlocks;

    /// @notice The key that commits each week's draw.
    address public keeper;

    /// @notice One week's draw.
    struct Draw {
        bytes32 seedHash;
        bytes32 ticketsRoot;
        uint256 ticketCount;
        uint256 prize; // USDC base units
        uint64 commitBlock;
        bool revealed;
        bool claimed;
        uint256 winnerIndex;
    }

    mapping(uint256 week => Draw) private _draws;

    /// @notice The keeper committed a week's draw.
    event Committed(
        uint256 indexed week, bytes32 seedHash, bytes32 ticketsRoot, uint256 ticketCount, uint256 prize, uint256 block_
    );
    /// @notice The seed was revealed and the winning ticket fixed.
    event Revealed(uint256 indexed week, bytes32 seed, bytes32 entropyBlockHash, uint256 winnerIndex);
    /// @notice The winner proved their ticket range and was paid.
    event DrawClaimed(uint256 indexed week, address indexed player, uint256 prize);
    /// @notice The admin voided an unrevealed draw (e.g. the reveal window was missed).
    event DrawVoided(uint256 indexed week);
    event KeeperSet(address indexed oldKeeper, address indexed newKeeper);

    /// @notice Only the keeper key may commit a draw.
    error LuckyLedger__NotKeeper(address sender, address keeper);
    /// @notice This week already has a draw.
    error LuckyLedger__AlreadyCommitted(uint256 week);
    /// @notice A draw needs tickets, a prize and a root.
    error LuckyLedger__BadDraw(uint256 ticketCount, uint256 prize);
    /// @notice No draw has been committed for this week.
    error LuckyLedger__NotCommitted(uint256 week);
    /// @notice The draw was already revealed.
    error LuckyLedger__AlreadyRevealed(uint256 week);
    /// @notice The seed doesn't match the committed hash.
    error LuckyLedger__BadSeed(bytes32 seedHash, bytes32 committed);
    /// @notice Too early to reveal (block numbers).
    error LuckyLedger__TooEarly(uint256 nowBlock, uint256 revealFromBlock);
    /// @notice The entropy block's hash is gone (more than 256 blocks ago). The admin can void the draw.
    error LuckyLedger__RevealWindowMissed(uint256 commitBlock, uint256 nowBlock);
    /// @notice The draw hasn't been revealed yet.
    error LuckyLedger__NotRevealed(uint256 week);
    /// @notice The prize was already claimed.
    error LuckyLedger__AlreadyClaimed(uint256 week);
    /// @notice The claimed range [from, to) doesn't contain the winning ticket.
    error LuckyLedger__NotTheWinner(uint256 winnerIndex, uint256 from, uint256 to);
    /// @notice The Merkle proof doesn't match the committed root.
    error LuckyLedger__BadProof();
    /// @notice An address that must be set was zero, or the delay was zero.
    error LuckyLedger__BadSettings();
    /// @notice The admin role can be handed over, but never thrown away.
    error LuckyLedger__AdminCantBeRemoved();

    constructor(IHousePool housePool, address keeper_, uint256 revealDelayBlocks_, address admin) Ownable(admin) {
        if (
            address(housePool) == address(0) || keeper_ == address(0) || revealDelayBlocks_ == 0
                || revealDelayBlocks_ >= BLOCKHASH_WINDOW
        ) revert LuckyLedger__BadSettings();
        HOUSE_POOL = housePool;
        revealDelayBlocks = revealDelayBlocks_;
        keeper = keeper_;
        emit KeeperSet(address(0), keeper_);
    }

    /// @notice The keeper commits a week's draw: hash of a secret seed, the tickets' Merkle root, how many tickets
    ///         there are, and the prize (USDC base units, paid from SURPRISE within its daily budget).
    function commit(uint256 week, bytes32 seedHash, bytes32 ticketsRoot, uint256 ticketCount, uint256 prize) external {
        if (msg.sender != keeper) revert LuckyLedger__NotKeeper(msg.sender, keeper);
        Draw storage d = _draws[week];
        if (d.commitBlock != 0) revert LuckyLedger__AlreadyCommitted(week);
        if (ticketCount == 0 || prize == 0 || ticketsRoot == bytes32(0) || seedHash == bytes32(0)) {
            revert LuckyLedger__BadDraw(ticketCount, prize);
        }
        d.seedHash = seedHash;
        d.ticketsRoot = ticketsRoot;
        d.ticketCount = ticketCount;
        d.prize = prize;
        d.commitBlock = SafeCast.toUint64(block.number);
        emit Committed(week, seedHash, ticketsRoot, ticketCount, prize, block.number);
    }

    /// @notice Reveals the seed (anyone who knows it) and fixes the winning ticket.
    function reveal(uint256 week, bytes32 seed) external returns (uint256 winnerIndex) {
        Draw storage d = _draws[week];
        if (d.commitBlock == 0) revert LuckyLedger__NotCommitted(week);
        if (d.revealed) revert LuckyLedger__AlreadyRevealed(week);
        bytes32 seedHash = keccak256(abi.encode(seed));
        if (seedHash != d.seedHash) revert LuckyLedger__BadSeed(seedHash, d.seedHash);
        uint256 revealFrom = revealFromBlock(week);
        if (block.number < revealFrom) revert LuckyLedger__TooEarly(block.number, revealFrom);
        bytes32 entropy = blockhash(d.commitBlock + 1);
        if (entropy == bytes32(0)) revert LuckyLedger__RevealWindowMissed(d.commitBlock, block.number);

        winnerIndex = uint256(keccak256(abi.encode(seed, entropy))) % d.ticketCount;
        d.revealed = true;
        d.winnerIndex = winnerIndex;
        emit Revealed(week, seed, entropy, winnerIndex);
    }

    /// @notice Pays the prize to the player whose ticket range [from, to) holds the winning ticket, proven against the
    ///         committed root. Anyone may submit it; the prize goes to `player`.
    function claim(uint256 week, address player, uint256 from, uint256 to, bytes32[] calldata proof)
        external
        nonReentrant
    {
        Draw storage d = _draws[week];
        if (!d.revealed) revert LuckyLedger__NotRevealed(week);
        if (d.claimed) revert LuckyLedger__AlreadyClaimed(week);
        if (d.winnerIndex < from || d.winnerIndex >= to) revert LuckyLedger__NotTheWinner(d.winnerIndex, from, to);
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(player, from, to))));
        if (!MerkleProof.verifyCalldata(proof, d.ticketsRoot, leaf)) revert LuckyLedger__BadProof();

        d.claimed = true;
        HOUSE_POOL.payDraw(player, d.prize, drawRef(week));
        // forge-lint: disable-next-line(reentrancy-events) nonReentrant guards the claim
        emit DrawClaimed(week, player, d.prize);
    }

    /// @notice Voids an unrevealed draw so the week can be committed again. Public in DrawVoided.
    function voidDraw(uint256 week) external onlyOwner {
        Draw storage d = _draws[week];
        if (d.commitBlock == 0) revert LuckyLedger__NotCommitted(week);
        if (d.revealed) revert LuckyLedger__AlreadyRevealed(week);
        delete _draws[week];
        emit DrawVoided(week);
    }

    /// @notice Replaces the keeper key.
    function setKeeper(address newKeeper) external onlyOwner {
        if (newKeeper == address(0)) revert LuckyLedger__BadSettings();
        address old = keeper;
        keeper = newKeeper;
        emit KeeperSet(old, newKeeper);
    }

    /// @notice Always refuses.
    function renounceOwnership() public pure override {
        revert LuckyLedger__AdminCantBeRemoved();
    }

    /// @notice A week's draw.
    function draw(uint256 week) external view returns (Draw memory) {
        return _draws[week];
    }

    /// @notice The first block at which a week's seed may be revealed (needs commitBlock + 1 to exist, too).
    function revealFromBlock(uint256 week) public view returns (uint256) {
        uint256 commitBlock = _draws[week].commitBlock;
        uint256 delay = revealDelayBlocks < 2 ? 2 : revealDelayBlocks;
        return commitBlock + delay;
    }

    /// @notice The HousePool ref a week's prize is paid under.
    function drawRef(uint256 week) public pure returns (bytes32) {
        return keccak256(abi.encode("tallyport.draw", week));
    }
}
