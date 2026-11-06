# Contracts

Solidity 0.8.26 with Foundry. Pinned libraries: OpenZeppelin 5.7.0, Uniswap v4-core 4.0.0, forge-std 1.17.0.
Chain: Ethereum Sepolia (Circle's test USDC, Uniswap v4, ENSv2); anvil locally. **USDC is the only money.**

## Layout

```
src/
  food/FoodToken.sol        FOOD: made once, burned when eaten. Players never hold it.
  food/FoodHook.sol         Uniswap hook: only FoodRouter trades; ±bandBps a day; floor and ceiling
  food/FoodRouter.sol       the only door into the FOOD/USDC pool (Buyer: MealCounter, Seller: Farm)
  food/MealCounter.sol      the only way a player buys food (signed MealTicket, ration shop fallback)
  food/Farm.sol             the supplier: keeper sells the harvest, proceeds straight to Treasury
  money/Treasury.sol        splits food revenue 60 FIXED / 10 SAFETY / 20 ops / 10 team
  money/HousePool.sol       three buckets, 4% a day each, per-human daily cap, rescue meals, draw prize
  money/CampaignEscrow.sol  sponsor campaigns: 10% fee, the 25% rule (I1), daily caps, claims, advances, refunds
  money/FloatManager.sol    holds sponsor USDC, cash buffer, ERC-4626 venues, yield harvest (never principal)
  money/Vouchers.sol        the EIP-712 structs and type strings (build spec 2.13)
  money/Links.sol           the small interfaces our contracts call each other through
  quests/SpiceMerchant.sol  the Spice Run's NPC: forwards the campaign's quest token to deliverTo
  quests/QuestToken.sol     MANGO, the demo sponsor's token
  quests/LuckyLedger.sol    the weekly draw: commit, reveal, Merkle claim, paid from SURPRISE
  mocks/MockUSDC.sol        local USDC (6 decimals, Circle's permit domain). Not money; anvil only
  mocks/MockYieldVault.sol  SIMULATED yield (ERC-4626 with an admin-funded drip). Demo only
  uniswap/UniswapPeriphery.sol  minimal PositionManager / UniversalRouter / Permit2 / Quoter interfaces
  names/ENSv2.sol, NameKit.sol  ENSv2 calls, coin type 60, tallyport.eth record keys and role bits
script/
  Deploy.s.sol              deploys and wires everything, seeds both pools, demo campaign, writes deployments/
  dev_chain.sh              anvil on D: + Uniswap's Sepolia bytecode at Sepolia addresses + Deploy + server env
  Smoke.s.sol               a player's meal, Universal Router swap and delivery against a local deployment
  uniswap/QuestPool.sol     quest pool seeding (PositionManager) and the Spice Run swap encoding
  anvil/                    UniswapOnAnvil.sol, fetch_uniswap.sh, uniswap/*.hex (Uniswap's Sepolia bytecode)
  names/                    CityNames.sol (the ENS steps), CityNames.s.sol (setUpCity, registerCity, registerPlayer)
deployments/
  <network>.config.json     launch numbers and external addresses (with source URLs)
  <network>.json            written by Deploy.s.sol; read by the server's chain crate
test/                       one file per contract, money invariants, a full-flow story, Uniswap and ENS fork tests
tools/spec_check.py         fails if code and docs/architecture/spec.json disagree
tools/dhv_why.py            explains any revert in plain words
```

## Running it

```
export HOME=/d/foundry/home PATH=/d/foundry:$PATH     # keep Foundry on D:
forge build && forge test                              # ENS fork tests skip without SEPOLIA_RPC_URL
SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com forge test --match-path "test/names/*"
forge fmt --check && forge lint -D warnings src && python tools/spec_check.py
script/dev_chain.sh                                    # local chain; prints the server's env
forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --slow --gas-estimate-multiplier 900   # Sepolia
python tools/verify_deployments.py .                  # then check deployments/sepolia.json against the chain
```

**Always run `tools/verify_deployments.py` after a Sepolia deploy.** `deployments/sepolia.json` is written from forge's
simulation, not from what landed. Two ways that goes wrong: the quest pool's `positionId` is a guess at Uniswap's shared
PositionManager's next id, and someone else can mint first (it happened on 7 Nov 2026: 41473 predicted, 41474 real);
and `--resume` after a dropped connection re-runs the script and rewrites the whole file with addresses that were never
deployed. The tool reads the broadcast's receipts and the chain, and `--fix` rewrites what's wrong. Never `--resume`
without running it afterwards.

**Sepolia gas (Nov 2026):** Sepolia's current gas schedule charges about 7× what Foundry's local simulation
predicts for contract creation (CampaignEscrow needs about 22.7M gas; forge estimates 3.2M). Without
`--gas-estimate-multiplier 900` the first deploy runs out of gas. Unused gas isn't charged; the 7 Nov 2026 deploy paid
0.0065 ETH in all. Check a single creation with `cast rpc eth_estimateGas` if in doubt.

## How we write code here

1. **One contract, one job.**
2. **Names say what they do.** Contracts are nouns, functions verbs, events past tense, errors `Contract__Problem`.
3. **Every error carries its numbers**: how much, and what the limit was.
4. **Every change emits an event**, so the server's indexer can replay history.
5. **Money is USDC base units.** 1,000,000 is 1 USDC. FOOD also has 6 decimals; prices are USDC per whole FOOD.
6. **Check, then change, then pay.**
7. **Reading is never blocked.**
8. **Every action has a ref, and a ref works once.**
9. **Short, one-way links between our contracts**, through the interfaces in `src/money/Links.sol`.
10. **Names, not addresses.** The server finds contracts by ENS name (and `deployments/<network>.json`).
11. **Money rules are tested first.** Every bug becomes a test before it's fixed.
12. **The spec and the code can't drift.** `tools/spec_check.py` runs in CI.
13. **No magic numbers.** Named constants with units; launch numbers in `deployments/<network>.config.json`.

Tests read like the game: `dollars(1)`, `usdcOf(0, 24_000)` is a $0.024 thali, `food(6)` is 6 servings, and keys
have names (`admin`, `keeper`, `sam`, `priya`, `sponsor`, `stranger`).
