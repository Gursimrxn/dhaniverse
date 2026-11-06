# The wallet, and food that only exists inside the game

The founder's decisions: FOOD must never be bought, held or traded outside the game; every player gets a Privy wallet;
and the game pays the gas from the operations share. This replaces today's server-derived player keys (one BIP-39 seed
in `server/crates/chain/src/wallets.rs`).

## Part 1. FOOD exists only inside the game

### What already holds (checked in `contracts/src/food/`)

- Only our router may trade in, or add stock to, the FOOD/USDC pool: `FoodHook` refuses any other sender (lines 223
  and 233).
- Only the Buyer role (`MealCounter`) may buy from the router, and only the Seller role (the `Farm`) may sell
  (`FoodRouter._checkRole`).
- A meal needs a server-signed EIP-712 ticket, and the caller must be the player named on it (`MealCounter.buyMeal`).
  The FOOD is bought and burned in the same transaction, so a player never holds any.

### The gap, and the fix

`FoodToken` is a plain ERC-20. FOOD sits in the pool, the farm, the ration-shop reserve and the admin's deploy
holding, and any of those could in principle transfer it to anyone. From there it could be listed in another pool,
for example a second Uniswap v4 pool with no hook. The fix makes that impossible:

- **A transfer allowlist on `FoodToken`.** A transfer goes through only if both the sender and the receiver are on the
  allowlist. Minting at deploy and burning are the only exceptions.
- **Both sides, not either.** Uniswap v4's PoolManager is a singleton that can `take` tokens out to any address. With an
  either-side rule, FOOD could leave the PoolManager to an outsider; with both sides, an outsider can never receive
  FOOD at all, so no other pool can ever be seeded.
- **The allowlist:** the PoolManager, `FoodRouter`, `Farm`, `MealCounter` (the ration reserve) and the deploy holder. It
  is set once by the deployer and then locked forever (`lockAllowlist()`). After that FOOD keeps today's promise:
  nothing anyone can change.
- **Tests (Foundry):** an outsider can't receive FOOD; a PoolManager `take` to an outsider reverts; an outsider can't
  swap in our pool, call the router or seed another pool; a forged, expired or reused meal ticket is refused; and a
  normal meal, a harvest sale and a ration-shop sale still work.
- `docs/architecture/spec.json` and `Contracts_Architecture.md` change with it, since CI checks the code against the
  spec, and the deploy scripts set the allowlist.

## Part 2. The wallet: Privy, and the game pays the gas

The founder's decisions: Privy for the wallet, and the game pays the gas from the operations share (in the technical
plan, 20% of food revenue goes to operations: paymaster gas and servers). No smart account, no paymaster service,
no bundler, no EIP-7702.

### What a player gets

- Sign-in with email, Google or a passkey through Privy, and an embedded wallet with no seed phrase, recoverable through
  Privy's login.
- No gas and no pop-ups. The wallet only signs messages, which is free and silent, and the game sends the transactions.
- The ENS name `name.dhaniverse.eth` points at the Privy wallet.

### How a transaction happens

- The player's wallet signs an EIP-712 authorization for one exact action. For a meal, that's a USDC
  `receiveWithAuthorization` (EIP-3009, which Circle's USDC supports) for at most the ticket's `maxUsdc`, with the
  ticket's `ref` as its nonce. For the Spice Run swap, it's a Permit2 signature.
- The server checks the action against the game's rules, submits it from its relayer key and pays the gas. The relayer
  is a key of its own, following the technical plan's "separate keys per role".
- The contracts check the player's signature, so the server can't spend a player's USDC without one for that exact
  amount and purpose.

### Contract changes

- `MealCounter.buyMealWithAuthorization(ticket, serverSig, usdcAuth)` checks the server's meal ticket and the player's
  authorization (to `MealCounter`, value ≤ `maxUsdc`, nonce = `ref`), pulls the USDC with `receiveWithAuthorization`,
  then buys and burns as today. The direct `buyMeal` path stays.
- **The Spice Run:** the swap runs through Uniswap's Universal Router with the player's tokens pulled by a Permit2
  signature, so the relayer can submit it. The delivery contract checks the swapped MANGO as today.
- Any other player action follows the same pattern. Vouchers and payouts already pay the player's address, so anyone
  can submit them.
- **Tests:** a relayed meal works and the relayer pays the gas; a reused, expired, over-limit or wrong-purpose
  authorization is refused; one meal's authorization can't be replayed for another.

### Gas money

- On Sepolia the relayer's ETH comes from the faucet.
- In production the operations share pays. A keeper swaps some of the Treasury's operations USDC for ETH whenever the
  relayer's balance falls under a threshold, and the server enforces a daily gas budget per player. The house reward
  pool is never touched: it pays the players' rewards.

### What changes on the server

- Players are identified by their Privy wallet address. The key derivation in `chain/src/wallets.rs` stays only for the
  server's own role keys.
- **New:** the relayer (queue, nonces, retries, gas price), the per-player daily gas budget, and checking each
  authorization before sending it.
- The wallet address goes in the encrypted Arkiv log. The link between a name and a wallet is never public.

## Order of work

1. **FOOD lockdown:** contracts, Foundry tests, the spec, deploy scripts. Foundry is installed to `D:\foundry`, since C:
   is full, and the contract submodules are initialised.
2. **Relayed calls:** the `MealCounter` authorization path and the Spice Run's Permit2 path, with tests.
3. **Server:** the relayer, gas budgets, wallet addresses, the Arkiv log.
4. **Browser:** Privy sign-in and silent signing. This needs the founder's Privy app ID. The onboarding scene around it
   waits for the founder's direction.
