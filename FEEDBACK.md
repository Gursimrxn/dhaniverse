# Uniswap developer feedback (Dhaniverse)

What we built on Uniswap, and what we ran into while building it. Everything here comes from our build log; nothing is
hypothetical.

## What we used
- **Uniswap v4 core** with a custom hook: `contracts/src/food/FoodHook.sol` gates the town's FOOD/USDC pool so only our
  router can trade or add stock, keeps the price between a floor and a ceiling, limits each day's move to a band
  (±15%), and records each day's totals so anyone can read the day's average price. `FoodRouter.sol` trades through
  `PoolManager.unlock` and stops part-way at the band instead of reverting.
- **v4 periphery on Sepolia**: PositionManager to seed a plain MANGO/USDC pool, **UniversalRouter + Permit2** for the
  player's own swap in the sponsored "Spice Run" quest, and **V4Quoter** for the minimum out.
- Code pointers: `contracts/src/food/FoodHook.sol` (hook permissions, `beforeSwap`/`afterSwap` band checks),
  `contracts/src/food/FoodRouter.sol` (`unlockCallback`, settlement), `contracts/script/uniswap/QuestPool.sol` (swap
  encoding), `server/crates/chain/src/plan.rs` (how the server builds the UniversalRouter call),
  `contracts/test/uniswap/QuestPool.t.sol` (seed through PositionManager, swap through UniversalRouter).

## What was hard, and what would have helped
1. **The deployed UniversalRouter's `ExactInputSingleParams` didn't match the newest periphery source.** The router on
   Sepolia takes five fields (`poolKey, zeroForOne, amountIn, amountOutMinimum, hookData`); the latest periphery adds a
   price-limit field. Encoding from the newest source silently produces calldata the deployed router rejects. A table of
   "which periphery commit is deployed at which address" next to the deployments page would have saved hours.
2. **Running v4 periphery locally.** There's no one-command way to get PoolManager + PositionManager + UniversalRouter +
   Permit2 + Quoter on a local anvil that matches a testnet. We copied Sepolia's runtime bytecode with `anvil_setCode`,
   and then had to restore PositionManager's constructor-set storage by hand (name, symbol, `nextTokenId = 1`). An
   official anvil state dump or a `v4-local` script would make local testing much easier.
3. **Attributing a swap to a user.** `PoolManager`'s `Swap` event names the router as `sender`, so an indexer that wants
   "did this player swap in this pool" has to fetch the transaction and use `tx.from`. A documented convention (e.g. an
   originator in `hookData`, or an event from UniversalRouter with the payer) would make swap-based quests and
   analytics far simpler.
4. **Hook addresses.** Mining a CREATE2 salt so the hook's address encodes its permission flags is well documented, but
   it's the step newcomers trip on first; a ready-made Foundry script helper in v4-core's test utils would help.
5. **Docs that helped most:** the v4 hooks permission table, `Hooks.validateHookPermissions`, and the
   `PoolManager.unlock` / settle / take flow.

## Feedback form
To do before submitting: fill in the Uniswap Developer Feedback Form and link it to this file.
