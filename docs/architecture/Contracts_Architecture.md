# Dhaniverse contracts: market, bank and names

**Status:** Being built, phase by phase, in contracts/. CI checks that every public function, event and error of ours has a plain-English line here. Earlier versions (v1, v2) are in archive/.  
**Version:** v3.1, Phase 0, Wed 5 Nov 2026.  
**Visual:** [Contracts_Architecture.html](Contracts_Architecture.html), which opens in any browser.  
**Sits on:** Game design v2: the food court, the bank, the Academy and the tutorial's name step. It adds no features; it says how the on-chain parts are built.

> Generated from `spec.json` by `build_docs.py`. Edit the spec, then run `python3 build_docs.py`, so this doc and the visual never disagree.

## Contents

0. [The 30-second version](#0-the-30-second-version)
1. [Five promises](#1-five-promises)
2. [How we work, every phase](#2-how-we-work-every-phase)
3. [The contracts, layer by layer](#3-the-contracts-layer-by-layer)
4. [Off-chain helpers](#4-off-chain-helpers)
5. [Two speeds: what waits for the chain](#5-two-speeds-what-waits-for-the-chain)
6. [When something breaks](#6-when-something-breaks)
7. [Phases, bottom to top](#7-phases-bottom-to-top)
8. [Decisions I've made for you](#8-decisions-ive-made-for-you)
9. [Arc Studio: where it fits](#9-arc-studio-where-it-fits)
10. [Rules of the code](#10-rules-of-the-code)
11. [Numbers the tests must hit](#11-numbers-the-tests-must-hit)
12. [Words](#12-words)
13. [Checked on 28 Oct](#13-checked-on-5-nov)

---

## 0. The 30-second version

Three things go on-chain, and each earns its place. The food market on Arc (FoodToken, FoodHook, FoodRouter), where food prices form in a Uniswap v4 pool. The bank on Arc (CityBank), which holds savings, pays interest at the Central Bank's public rate and runs loans by rules nobody can quietly change. And player names on ENSv2 (Sepolia): every player is a name like sam.dhaniverse.eth, which is how they appear and how friends pay them. That's four contracts of ours, standing on Uniswap's, Arc's and ENS's own. Everything else runs on our Rust server, and players never sign anything or wait for a chain. The contracts, their tests and this map are all in this repository.

In numbers: 4 contracts of ours and 6 that aren't ours, 57 functions in all. Every one is listed in §3.

**What I need from you:**

1. Approve the three on-chain pieces: the food market, the bank and ENS names.
2. Confirm the game, server and contracts in this repository are the ones we build on.
3. Confirm where the code lives (decision 1): a public repository.
4. Gather test funds before the first phase: about 50 Arc testnet USDC, 0.5 Sepolia ETH, and Sepolia test USDC for the dhaniverse.eth fee.
5. Keep these planning notes in the repository, in step with the contracts.
6. Install the Arc Studio CLI and log in with arc-studio login --paste.

## 1. Five promises

- ⚡ **The game never waits for the chain.** Players never sign anything or pay gas. Walking, working and eating never touch a chain. Bank actions confirm in about a second behind an animation, and names catch up in the background.
- 🔎 **Every error names itself.** No vague failures. Each refusal says which contract, what went wrong, and the numbers that caused it. Our tool, dhv why, adds the plain-English meaning and the exact file and line.
- 🧯 **If a chain breaks, the city doesn't.** If Arc or Sepolia is slow, or a key is switched off, the game keeps running: menus keep the last prices, bank actions wait in order, and names show from our database.
- 🔧 **Fixable without losing anything.** A broken contract is replaced and its ENS name repointed, and the server follows the name. Every fix starts as a failing test and runs on a test world first.
- 📖 **Every function in plain words.** Every function on every contract is listed here: who presses it, when, and what happens. Once code exists, CI fails if a public function has no plain-English line in this spec.

## 2. How we work, every phase

1. **Brief.** Before any code: a short page with this phase's contracts, functions and decisions. You say go, or change it.
2. **Build.** I write the code and its tests. Money rules get their tests first.
3. **Prove.** Every test green, the numbers below hit exactly, and Arc Studio gives a second opinion.
4. **Show.** A phase report: what was built, what each function does, test results, anything that changed from this map, and one command to run it yourself.
5. **You review.** Then it merges and the next phase starts.

## 3. The contracts, layer by layer

Layers are built bottom to top (§7).

| Layer | Contract | What it is | Kind | Upgrade | Off switch |
|---|---|---|---|---|---|
| Layer 0 | USDC | Arc's dollar | Not ours | Arc's (we don't control it) | n/a |
| Layer 0 | FoodToken | FOOD token (ERC-20) | Token | Fixed (a plain ERC-20) | No |
| Layer 1 | PoolManager | Uniswap v4 core | Not ours | Uniswap's (we don't control it) | n/a |
| Layer 1 | FoodHook | Uniswap hook: price rules | Uniswap hook | Fixed, as Uniswap expects (a bug means a new hook and pool) | No (take FoodRouter's keys away instead) |
| Layer 2 | FoodRouter | The only door in | Contract (ours) | Fixed (replace if broken; the pool stays) | Yes: take a key's role away, and that key's trading stops |
| Layer 3 | CityBank | Savings, loans and the rate | Contract (ours) | Fixed (replace if broken, and repoint bank.dhaniverse.eth) | Yes: take the teller key's role away, and the bank stops taking actions; every balance stays safe and readable |
| Layer 4 | ENSRegistry | ENSv2's .eth registry and registrar | Not ours | ENS's (we don't control it) | n/a |
| Layer 4 | NameRegistry | dhaniverse.eth's registry (our copy of ENS's code) | Not ours | ENS's code; our copy | Take the names key's registrar role away |
| Layer 4 | NameResolver | The records: two resolvers (our copies of ENS's code) | Not ours | ENS's code; our copies | Take a key's record role away |
| Layer 4 | ENSLookup | Universal Resolver and reverse registrar | Not ours | ENS's (we don't control it) | n/a |

### Layer 0 · Money: the tokens on Arc: USDC, and FOOD for the pool

Phase 0–1 · Food court · Bank · `src/food`

#### 💵 USDC · Arc's dollar

**What it is.** The money the pool trades against and the bank holds. On Arc, USDC also pays for gas.

**In the game.** Never seen. Players spend coins; on-chain, 1 coin is 0.0001 USDC.

- **File:** `Arc's USDC, ERC-20 view at 0x3600…0000 (6 decimals)`
- **Kind:** Not ours
- **Upgrade:** Arc's (we don't control it)
- **Off switch:** n/a
- **Stores:** who holds how much USDC
- **Calls or reads:** nothing (other contracts read it)

**Functions (1)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `transfer · transferFrom · approve · balanceOf` | FoodRouter, CityBank, the server's keys | Every trade | A standard token. |

**Events**

| Event | Means |
|---|---|
| `Transfer · Approval` | USDC moved. |

#### 🍲 FoodToken · FOOD token (ERC-20)

**What it is.** 1 FOOD is one serving of the city's food. Every FOOD is created once, at deploy. Nobody can make more, and eaten FOOD is burned.

**In the game.** Players never see it. A chai uses 1 FOOD, a burger 4.5, a restaurant meal 8.

- **File:** `src/food/FoodToken.sol`
- **Kind:** Token
- **Upgrade:** Fixed (a plain ERC-20)
- **Off switch:** No
- **Stores:** who holds how much FOOD
- **Calls or reads:** nothing (other contracts read it)

**Functions (3)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `constructor(holder, supply)` | The deploy script | Once | Creates all the FOOD there will ever be and gives it to the admin key, which hands stock to the supplier and the pool. |
| `transfer · transferFrom · approve · allowance · balanceOf · totalSupply · name · symbol · decimals` | Anyone | Any time | A standard ERC-20: move FOOD, let someone else move it for you, and read balances. 6 decimals, like USDC. |
| `burn(amount)` | FoodRouter (anyone can burn their own) | Every meal batch | Destroys FOOD that's been eaten, so the city's food supply really shrinks. |

**Events**

| Event | Means |
|---|---|
| `Transfer · Approval` | FOOD moved, or was burned (a transfer to nobody). |

**Errors**

| Error | Means |
|---|---|
| `FoodToken__ZeroSupply()` | A deploy with no FOOD at all is a mistake, so it's refused. |
| `ERC20InsufficientBalance(sender, balance, needed)` | OpenZeppelin's standard error: not enough FOOD. |
| `ERC20InvalidReceiver(receiver)` | OpenZeppelin's: FOOD can't be sent or minted to the zero address. |

### Layer 1 · Market rules: uniswap's engine, and our hook with the price rules and the day's price

Phase 1 · Food court · `src/food`

#### 🌀 PoolManager · Uniswap v4 core

**What it is.** Uniswap's engine. It holds the FOOD/USDC pool, does the trade maths, and calls FoodHook during every trade.

**In the game.** City Hall's food price board moves when it trades.

- **File:** `Uniswap v4 PoolManager, already on Arc testnet at 0x8366a39C…0951`
- **Kind:** Not ours
- **Upgrade:** Uniswap's (we don't control it)
- **Off switch:** n/a
- **Stores:** the pool's FOOD and USDC, and its price
- **Calls or reads:** FoodHook (on every trade)

**Functions (1)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `initialize · modifyLiquidity · swap · unlock` | FoodRouter; the admin key (initialize, once) | Setup and every trade | Uniswap's own functions. Our router presses them, and our hook's rules run inside. |

**Events**

| Event | Means |
|---|---|
| `Initialize · ModifyLiquidity · Swap` | Uniswap's own events. |

**Errors**

| Error | Means |
|---|---|
| `WrappedError(target, selector, reason, details)` | Uniswap wraps our hook's refusals in this. dhv why unwraps it. |
| `PriceLimitAlreadyExceeded(price, limit)` | Uniswap's: the price already sits at the limit asked for. FoodRouter checks first, so we shouldn't see it. |

#### ⚖️ FoodHook · Uniswap hook: price rules

**What it is.** Rules that run inside every food trade. Only FoodRouter may trade or add stock. In one city day (one real hour at launch) the price moves at most 5% either way from the day's opening price, and it always stays between 5 and 30 coins per FOOD. Each day's trades are added up to give that day's price.

**In the game.** The ▲▼ arrows on every menu, and the food price on City Hall's board.

- **File:** `src/food/FoodHook.sol`
- **Kind:** Uniswap hook
- **Upgrade:** Fixed, as Uniswap expects (a bug means a new hook and pool)
- **Off switch:** No (take FoodRouter's keys away instead)
- **Stores:** the one pool it serves; FoodRouter's address; the floor, the ceiling, the day length and the first day's start (fixed at deploy); each day's opening price, USDC total and FOOD total
- **Calls or reads:** PoolManager (reads the live price)

**Functions (15)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `constructor(manager, admin, router, usdc, food, floor, ceiling, dayLength)` | The deploy script | Once | Fixes the floor, the ceiling (in cents per FOOD) and the day length. Refuses settings that make no sense, and refuses to exist at an address whose permission bits don't match its four hooks. |
| `beforeInitialize` | Uniswap, automatically | Once, at setup | Allows only our FOOD/USDC pool, only once, only from the admin key, and only at a starting price between the floor and the ceiling. |
| `beforeAddLiquidity` | Uniswap, automatically | When stock is added | Allows it only through FoodRouter, so nobody else can change how fast prices move. |
| `beforeSwap` | Uniswap, automatically | Every trade | Allows only FoodRouter. On the day's first trade, notes the opening price. |
| `afterSwap` | Uniswap, automatically | Every trade | Refuses a trade that leaves the price outside today's limit: 5% either way from the opening price, and inside the floor and ceiling. Adds the trade to today's totals. |
| `afterInitialize · afterAddLiquidity · beforeRemoveLiquidity · afterRemoveLiquidity · beforeDonate · afterDonate` | Nobody | Never | Hooks we don't use. Uniswap never calls them for our pool, and they refuse if anyone else does. |
| `setRouter(router)` | Admin key | Only if FoodRouter is replaced | Points the hook at a new FoodRouter. The pool, its money and its history stay. Zero means trading is off. |
| `owner · pendingOwner · transferOwnership · acceptOwnership` | Admin key; the new admin key accepts | Rarely | Hands the admin role to another key in two steps: nothing changes until the new key accepts, so a typo can't lose control. |
| `renounceOwnership` | Nobody | Never | Always refuses. Without an admin, a broken router could never be replaced. |
| `today()` *(read)* | Anyone | Any time | Today's day number, counted from the block clock since deploy. |
| `band()` *(read)* | FoodRouter, the server | Before every trade | Today's lowest and highest allowed price and the live price, as Uniswap sqrt prices. FoodRouter uses them as the limit for its trades. |
| `dayPrice(day)` *(read)* | The server's price reader | Once a city day | That day's price in cents per FOOD: total USDC ÷ total FOOD, rounded down. Zero if nothing traded. |
| `dayTotals(day)` *(read)* | Anyone | Any time | That day's opening price (cents per FOOD), USDC total and FOOD total, so anyone can check dayPrice. |
| `centsPerFood(sqrtPrice)` *(read)* | Anyone, dhv why | Any time | Turns one of Uniswap's sqrt prices into cents per FOOD that people can read. |
| `settings · poolManager · router · getHookPermissions` *(read)* | Anyone, dhv doctor | Any time | What was fixed at deploy, the current router, and the four hooks this contract uses. |

**Events**

| Event | Means |
|---|---|
| `DayOpened(day, openPrice)` | The first trade of a new day. Today's limit is set around this price (cents per FOOD). |
| `TradeCounted(day, usdc, food, priceAfter)` | A trade counted toward today's price. |
| `RouterSet(oldRouter, newRouter)` | FoodRouter was set or replaced. |
| `OwnershipTransferStarted · OwnershipTransferred` | The admin role is being handed over, or was. |

**Errors**

| Error | Means |
|---|---|
| `FoodHook__BadSettings(floor, ceiling, dayLength)` | The deploy settings make no sense: the floor must be above zero and below the ceiling, and a day must last at least a second. |
| `FoodHook__NotPoolManager(caller)` | Hook functions can only be called by Uniswap's PoolManager. |
| `FoodHook__HookNotUsed()` | This hook function is switched off for our pool. |
| `FoodHook__NotAdmin(sender)` | Only the admin key can create the pool. |
| `FoodHook__PoolExists()` | This hook serves one pool, and it already exists. |
| `FoodHook__WrongTokens(currency0, currency1)` | The pool must be FOOD against USDC. |
| `FoodHook__StartOutsideBounds(price, floor, ceiling)` | The starting price must be between the floor and the ceiling (cents per FOOD). |
| `FoodHook__NotRouter(sender)` | Trades and new stock must come through FoodRouter. |
| `FoodHook__OutsideBand(price, low, high)` | The trade would move the price past today's limit, the floor or the ceiling (cents per FOOD). |
| `FoodHook__AdminCantBeRemoved()` | The admin role can be handed over, but never thrown away. |
| `HookAddressNotValid(hooks)` | Uniswap's: the hook's address doesn't carry the permission bits for its hooks. Mine a new address. |
| `OwnableUnauthorizedAccount(account)` | OpenZeppelin's: only the admin key can do this. |

### Layer 2 · The door: the only way into the food pool. Two server keys trade through it

Phase 2 · Food court · `src/food`

#### 🚪 FoodRouter · The only door in

**What it is.** The only way to trade FOOD. Two server keys use it: the food court key buys what the city ate, and the supplier key sells new food. At today's limit it stops the trade part-way instead of failing, and reports how much it filled. Every trade has a ref that works once. A reentrancy guard stops anything calling back into a trade.

**In the game.** Every meal anyone eats ends up here a few minutes later, in one batch.

- **File:** `src/food/FoodRouter.sol`
- **Kind:** Contract (ours)
- **Upgrade:** Fixed (replace if broken; the pool stays)
- **Off switch:** Yes: take a key's role away, and that key's trading stops
- **Stores:** the one pool it trades; which key has which role (Buyer or Seller); refs already used
- **Calls or reads:** PoolManager, FoodHook (today's limit), USDC, FoodToken (burns eaten FOOD)

**Functions (9)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `constructor(manager, hook, admin, tickSpacing)` | The deploy script | Once | Learns the pool from FoodHook (FOOD against USDC, no fee) and sets the admin key. |
| `buyFood(foodWanted, ref) → (foodBought, usdcPaid)` | Buyer role: the food court key | Every few minutes | Buys up to foodWanted FOOD with the key's USDC, stopping at today's limit, then burns it. If the price is already at the limit, buys nothing and still succeeds. A ref works once. |
| `sellFood(foodOffered, ref) → (foodSold, usdcGot)` | Seller role: the supplier key | Through the day | Sells up to foodOffered FOOD for USDC, stopping at today's limit. Only the FOOD actually sold leaves the supplier. A ref works once. |
| `addLiquidity(liquidity) · removeLiquidity(liquidity)` | Admin key | Setup; moving to a new router; recycling a test world | Puts FOOD and USDC into the pool, or takes them back to the admin key, across the full price range. |
| `setRole(key, role)` | Admin key | Setup; switching a key off | Gives a key the Buyer or Seller role, or takes it away (None). This is the off switch. |
| `owner · pendingOwner · transferOwnership · acceptOwnership` | Admin key; the new admin key accepts | Rarely | Hands the admin role to another key in two steps, so a typo can't lose control. |
| `renounceOwnership` | Nobody | Never | Always refuses. Without an admin, nobody could switch a leaked key off. |
| `roleOf(key) · refUsed(ref) · poolKey()` *(read)* | Anyone, dhv doctor | Any time | A key's role, whether a ref has been used, and the pool this router trades. |
| `unlockCallback(data)` | PoolManager only | Inside a trade | Uniswap's settlement plumbing. Anyone else is refused, so nobody can make another key pay. |

**Events**

| Event | Means |
|---|---|
| `FoodBought(day, buyer, wanted, bought, usdcPaid, ref)` | A batch of eaten food was bought and burned. bought below wanted means today's limit was reached. |
| `FoodSold(day, seller, offered, sold, usdcGot, ref)` | The supplier sold food. sold below offered means today's limit was reached. |
| `LiquidityChanged(by, liquidityDelta, usdc, food)` | The pool's stock changed. |
| `RoleSet(key, role)` | A key got or lost a role. |
| `OwnershipTransferStarted · OwnershipTransferred` | The admin role is being handed over, or was. |

**Errors**

| Error | Means |
|---|---|
| `FoodRouter__NotAllowed(caller, has, needs)` | This key doesn't have the role for this function, or it was switched off. |
| `FoodRouter__RefUsed(ref)` | This batch already went through. The retry was blocked, so nobody paid twice. |
| `FoodRouter__ZeroAmount()` | Asked to trade or move nothing. |
| `FoodRouter__OnlyPoolManager(caller)` | Only Uniswap may call the settlement plumbing. |
| `FoodRouter__AdminCantBeRemoved()` | The admin role can be handed over, but never thrown away. |
| `ReentrancyGuardReentrantCall()` | OpenZeppelin's: something tried to call back into a trade while it was running. |
| `OwnableUnauthorizedAccount(account)` | OpenZeppelin's: only the admin key can do this. |

### Layer 3 · The bank: savings, loans and the Central Bank's rate

Phase 3 · Bank · Academy tiers 2, 3, 5 · `src/bank`

#### 🏦 CityBank · Savings, loans and the rate

**What it is.** The city's bank, with its rules in public. It holds every player's savings in USDC and pays interest at the Central Bank's rate minus 2% when each player's month closes. Savings are never lent out: the bank lends only its own reserve, so savings are always there to withdraw. It runs loans: it works out each EMI, collects it when the player's month closes, and reprices the loan when the rate changes, the way the player chose. One open loan at a time, unless the first has three on-time EMIs and no misses.

**In the game.** The Bank building: savings that grow every month, the scooter loan and later a home loan, the ✓ on every EMI, and paying a friend by name.

- **File:** `src/bank/CityBank.sol`
- **Kind:** Contract (ours)
- **Upgrade:** Fixed (replace if broken, and repoint bank.dhaniverse.eth)
- **Off switch:** Yes: take the teller key's role away, and the bank stops taking actions; every balance stays safe and readable
- **Stores:** each account's savings, its last closed month, and its open loans (two slots); each loan: product, what's left to pay, rate, EMI, months to the original end date, on-time and missed counts, the player's rate-change choice; the Central Bank's rate, and each product's spread and limits (fixed at deploy); the books: everyone's savings, the reserve, and what borrowers owe; refs already used, and which key has which role (Teller or Central Bank)
- **Calls or reads:** USDC

**Functions (16)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `constructor(usdc, admin, startRate, scooterTerms, homeTerms)` | The deploy script | Once | Sets the starting rate (5.50%) and fixes each loan product's spread, largest loan and longest term. Nobody can change these later. |
| `deposit(account, amount, ref)` | Teller role (the server) | When a player saves | Moves USDC from the teller key into the bank and adds it to the account's savings. |
| `withdraw(account, amount, ref)` | Teller role | When a player takes money out | Takes it from savings and sends the USDC back to the teller key, which puts the coins in the player's pocket. |
| `transfer(from, to, amount, ref)` | Teller role | When a player pays a friend by name | Moves savings from one account to another. The server finds 'to' from the friend's ENS name. |
| `openLoan(account, product, principal, months, ref) → loanId` | Teller role | When a player takes a loan (after Academy tier 3) | Checks the product's limits and the one-at-a-time rule, sets the rate (the Central Bank's rate plus the product's spread), works out the EMI, and pays the money from the reserve to the teller key, which buys the item in the game. |
| `closeMonth(account, month, ref)` | Teller role | When the player's month ends | Only the next month, never a skipped or repeated one. Pays interest on savings, reprices loans if the rate changed, then collects each EMI from savings. If savings are short, it records a missed EMI (that month's interest is added to what's owed) instead of failing. Three misses in a row are recorded as a default; the loan stays open. |
| `setRepayChoice(loanId, keepEmi)` | Teller role | When the player answers the rate-change card | Keep the EMI and pay for longer (the default), or keep the end date and pay more each month. Used at the next rate change. |
| `setRate(rateBps, cpiBps, reportHash)` | Central Bank role | After each Central Bank meeting | Sets the city's rate. It moves at most 0.50% at a time and stays between 0% and 15%. Records the CPI and a fingerprint of the published report. |
| `fundReserve(amount) · withdrawReserve(amount)` | Admin key | Setup; top-ups; recycling a test world | Adds the city's own USDC to the reserve, or takes reserve money back. Savings can never be taken this way. |
| `setRole(key, role)` | Admin key | Setup; switching a key off | Gives a key the Teller or Central Bank role, or takes it away. This is the off switch: balances stay safe and readable. |
| `owner · pendingOwner · transferOwnership · acceptOwnership` | Admin key; the new admin key accepts | Rarely | Hands the admin role to another key in two steps, so a typo can't lose control. |
| `renounceOwnership` | Nobody | Never | Always refuses. Without an admin, nobody could switch a leaked key off. |
| `account(addr) · loan(loanId) · rates() · totals()` *(read)* | Anyone | Any time | A balance, its month and open loans; one loan; today's rates; and the bank's books (savings, reserve, owed). |
| `terms(product) · savingsRateBps() · emiFor(principal, rateBps, months)` *(read)* | Anyone | Any time | A product's fixed terms, the savings rate, and the EMI maths on its own, so anyone can check a loan's numbers. |
| `refUsed(ref) · roleOf(key)` *(read)* | Anyone, dhv doctor | Any time | Whether a ref has been used, and a key's role. |
| `SAVINGS_SPREAD_BPS · RATE_MAX_BPS · RATE_MAX_STEP_BPS · ON_TIME_FOR_SECOND_LOAN · MISSES_FOR_DEFAULT` *(read)* | Anyone | Any time | The bank's fixed rules as numbers: savings earn the rate minus 2%; the rate stays at or under 15% and moves at most 0.50% at a time; a second loan needs 3 on-time EMIs; 3 misses in a row is a default. |

**Events**

| Event | Means |
|---|---|
| `Deposited(account, amount, ref) · Withdrawn(account, amount, ref)` | Savings went in or out. |
| `Transferred(from, to, amount, ref)` | A player paid another player. |
| `LoanOpened(loanId, account, product, principal, rateBps, months, emi)` | A loan started. Anyone can check the EMI with emiFor. |
| `MonthClosed(account, month, interest)` | A player's month closed, and their savings earned this much. |
| `EmiPaid(loanId, month, interest, principal, left) · EmiMissed(loanId, month, missedInARow)` | A payment made or missed. This is the public credit history the bureau reads. |
| `LoanRepriced(loanId, oldRateBps, newRateBps, emi, monthsLeft)` | The rate changed, and the loan followed the player's choice. |
| `LoanRepaid(loanId) · LoanDefaulted(loanId, month)` | A loan finished, or missed three in a row. |
| `RepayChoiceSet(loanId, keepEmi)` | The player answered the rate-change card. |
| `RateSet(oldBps, newBps, cpiBps, reportHash)` | The Central Bank decided. The report's fingerprint proves which report it was. |
| `ReserveChanged(by, change, reserve)` | The admin added to or took from the reserve. |
| `RoleSet(key, role)` | A key got or lost a role. |
| `OwnershipTransferStarted · OwnershipTransferred` | The admin role is being handed over, or was. |

**Errors**

| Error | Means |
|---|---|
| `CityBank__NotAllowed(caller, has, needs)` | This key doesn't have the role for this function, or it was switched off. |
| `CityBank__RefUsed(ref)` | This action already went through. The retry was blocked. |
| `CityBank__ZeroAmount()` | An amount of zero. |
| `CityBank__WrongMonth(account, expected, got)` | Months close one at a time, in order. This one was already closed, or one was skipped. |
| `CityBank__NotEnoughSavings(account, has, needs)` | Not enough savings to withdraw or pay that much. |
| `CityBank__OneAtATime(account, openLoans)` | A new loan has to wait until the current one has three on-time EMIs and no misses. |
| `CityBank__OverLimit(product, principal, max) · CityBank__TooLong(product, months, max)` | The loan is bigger or longer than the product allows. |
| `CityBank__NotEnoughCash(cash, needed)` | The reserve is too small to lend that much, or to pay this month's savings interest. The admin tops it up and the month closes on retry. |
| `CityBank__RateStepTooBig(oldBps, newBps, maxStepBps) · CityBank__RateOutOfBounds(rateBps, minBps, maxBps)` | The Central Bank tried to move the rate too far, or outside 0% to 15%. |
| `CityBank__UnknownLoan(loanId)` | No such loan, or it's already repaid. |
| `CityBank__AdminCantBeRemoved()` | The admin role can be handed over, but never thrown away. |
| `ReentrancyGuardReentrantCall()` | OpenZeppelin's: something tried to call back into a money move while it was running. |
| `OwnableUnauthorizedAccount(account)` | OpenZeppelin's: only the admin key can do this. |

### Layer 4 · Names (Sepolia): eNSv2: every player's name, its records, and the city's directory

Phase 4 · Tutorial · profiles · paying by name · `script/names`

#### 🗂️ ENSRegistry · ENSv2's .eth registry and registrar

**What it is.** ENS's own registry for .eth names. We register dhaniverse.eth here once, and point it at our own registry for the city's names.

**In the game.** Never seen. It's what makes our names real ENS names that any app can read.

- **File:** `ENS's ETHRegistry and ETHRegistrar on Sepolia (addresses from ENS's deployments page, never hard-coded)`
- **Kind:** Not ours
- **Upgrade:** ENS's (we don't control it)
- **Off switch:** n/a
- **Stores:** who owns dhaniverse.eth, and which registry and resolver it uses
- **Calls or reads:** nothing (other contracts read it)

**Functions (2)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `commit(commitment) · register(label, owner, secret, subregistry, resolver, duration, paymentToken, referrer)` | ENS admin key | Once, at go-live | Registers dhaniverse.eth in two steps a minute apart (so nobody can snipe it), pointing it at our registry and the directory resolver from the start. ENSv2 takes the fee in a stablecoin: about 8 test-USDC a year on Sepolia. |
| `getRegisterPrice · isAvailable · ETH_REGISTRY` *(read)* | The setup script | Before registering | The fee, whether the name is free, and which registry the registrar writes to (checked against the root, so we never talk to a stale deployment). |

**Events**

| Event | Means |
|---|---|
| `ENS's own registry events` | dhaniverse.eth was registered or repointed. |

**Errors**

| Error | Means |
|---|---|
| `CommitmentTooNew(commitment, validFrom, now) · CommitmentTooOld(commitment, validTo, now)` | Registered too soon after committing (wait a minute), or too late (commit again). |
| `NameNotAvailable(label)` | Someone already holds that .eth name. |
| `DurationTooShort(duration, minDuration) · PaymentTokenNotSupported(token)` | ENS's registration rules: at least 28 days, paid in a stablecoin it accepts. |

#### 📇 NameRegistry · dhaniverse.eth's registry (our copy of ENS's code)

**What it is.** Holds every name under dhaniverse.eth. Each name is a token owned by the player's address, and ENSv2 roles say who can change what. Player names get no transfer role, so they can't be sold or taken.

**In the game.** sam.dhaniverse.eth and priya.dhaniverse.eth for players; bank.dhaniverse.eth and market.dhaniverse.eth for the city's own contracts.

- **File:** `ENS's UserRegistry, deployed for us through ENS's VerifiableFactory on Sepolia`
- **Kind:** Not ours
- **Upgrade:** ENS's code; our copy
- **Off switch:** Take the names key's registrar role away
- **Stores:** each name's owner, resolver and expiry; who holds which ENSv2 role
- **Calls or reads:** nothing (other contracts read it)

**Functions (4)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `deployProxy(implementation, salt, data) (ENS's VerifiableFactory)` | ENS admin key | Once, at go-live | Deploys our copy of ENS's registry at an address anyone can predict, with the admin holding every role and the names key allowed only to register and renew. |
| `register(label, owner, registry, resolver, roleBitmap, expiry)` | Names key (ROLE_REGISTRAR); admin key for the city's own names | When a player picks a name | Creates sam.dhaniverse.eth, owned by Sam's address, using the players' resolver, with no roles at all for the owner: it can't be transferred, sold or repointed. |
| `setParent(parent, label)` | ENS admin key | Once | Links our registry back to dhaniverse.eth in the .eth registry. |
| `findTokenId · ownerOf · getSubregistry · getResolver` *(read)* | The server, tests | Before every write | A name's current token and owner, and where its records live. Read fresh every time, as ENS asks. |

**Events**

| Event | Means |
|---|---|
| `ENS's registry events (name registered, roles changed)` | The indexer builds the list of names from these. |

**Errors**

| Error | Means |
|---|---|
| `EACUnauthorizedAccountRoles(resource, roleBitmap, account)` | ENSv2's role check: this key doesn't hold the role for that action (for example a stranger trying to give out names). |
| `LabelAlreadyRegistered(label) · LabelExpired(tokenId)` | The name is already someone's, or it ran out (the names key renews names yearly). |
| `TransferDisallowed(tokenId, from)` | Player names can't be transferred: the owner holds no transfer role. |

#### 🪪 NameResolver · The records: two resolvers (our copies of ENS's code)

**What it is.** Holds each name's records: its Arc address, avatar, Academy tier and, if the player opts in, credit level. ENSv2's per-record roles decide which key may write each one. The city's own names sit on a second resolver only the admin can write, because ENSv2 roles can limit a key to one record type but not to one name.

**In the game.** The profile card when you tap a player: avatar, Academy badge and, if they chose to show it, their credit level.

- **File:** `ENS's PermissionedResolver, deployed twice for us through VerifiableFactory on Sepolia: one for players' names, one for the city's`
- **Kind:** Not ours
- **Upgrade:** ENS's code; our copies
- **Off switch:** Take a key's record role away
- **Stores:** each name's records; which key may write which record
- **Calls or reads:** nothing (other contracts read it)

**Functions (3)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `deployProxy(implementation, salt, data) (ENS's VerifiableFactory)` | ENS admin key | Once, at go-live | Deploys our two copies of ENS's Permissioned Resolver: one for players' records, one for the city's directory. |
| `grantSetterRoles(setter, account)` | ENS admin key | Once, at go-live; switching a key off | Gives each key exactly one kind of record: names key (Arc address, default address, avatar, description), Academy key (tier only), bureau key (credit level only). This is ENSv2's per-record role. |
| `multicall(calls) · setAddress(name, coinType, address) · setText(name, key, value)` | Names key; Academy key (tier); bureau key (credit); admin key (directory) | A new name; a finished tier; a month closing; a replaced contract | Writes records. Each key's writes are refused outside its own record type. |

**Events**

| Event | Means |
|---|---|
| `ENS's resolver events (address and text changed)` | A record changed; apps refresh it. |

**Errors**

| Error | Means |
|---|---|
| `EACUnauthorizedAccountRoles(resource, roleBitmap, account)` | A key tried to write a record it has no role for: the names key writing a credit level, or anyone but the admin touching the directory. |

#### 🔍 ENSLookup · Universal Resolver and reverse registrar

**What it is.** How anyone reads ENS. One entry point turns any name into an address for any chain, reads text records, and turns an address back into its primary name.

**In the game.** Typing a friend's name to pay them, and names on receipts instead of 0x numbers.

- **File:** `ENS's UniversalResolverV2 and default reverse registrar on Sepolia, reached through the alloy library`
- **Kind:** Not ours
- **Upgrade:** ENS's (we don't control it)
- **Off switch:** n/a
- **Stores:** primary names: which name each address chose
- **Calls or reads:** nothing (other contracts read it)

**Functions (3)**

| Function | Who calls it | When | What happens |
|---|---|---|---|
| `resolve(name, data)` *(read)* | The server, through alloy's ENS support | Paying by name; loading a profile; startup | A name's Arc address, avatar or tier. Works for any ENS name, not just ours. |
| `reverse(address, coinType)` *(read)* | The server | Showing receipts | An address's primary name, then a forward check that the name points back. |
| `setName(account, name) on ENS's default reverse registrar adapter` | The player's own address (its key is server-held) | Once, after the name is created | Makes sam.dhaniverse.eth the primary name of Sam's address on every EVM chain, Arc included. It needs a few cents of Sepolia ETH in that address. |

**Events**

| Event | Means |
|---|---|
| `ENS's reverse-registrar events` | A primary name was set. |

**Errors**

| Error | Means |
|---|---|
| `UnauthorizedNamer(namer)` | Only the address itself can set its own primary name. |

## 4. Off-chain helpers

Our Rust server runs the whole game. These helpers are the only parts that touch a chain, and each key they hold can press only certain functions. Our kit for them: ABIs, typed Rust bindings and the error catalog (Phase 6).

| Helper | What it does |
|---|---|
| 🍽️ Meal batcher | Adds up the FOOD every meal uses. Every few minutes, the food court key sends one buyFood with a new ref. |
| 🚚 City supplier | The supplier key sells each day's food arrivals in small slices. Festivals and harvests change the amounts; when rates are high, it pushes prices less hard. |
| 📈 Price reader | Once a city day, reads yesterday's dayPrice and turns it into the food index: menu prices, the ▲▼ arrows, and the CPI's food part. |
| 🏦 Teller | Turns bank actions in the game into CityBank calls: save, withdraw, pay by name, take a loan, close a month. Tops up savings from pocket first if the player chose auto-pay. |
| 🏛️ Central Bank | The AI committee that decides the rate on our server, then sends one setRate with the CPI and a fingerprint of its report. |
| 🪪 Name registrar | Registers each new player's name, writes its address and profile records, and sets the primary name from the player's address. |
| 🎓 Academy writer | Writes com.dhaniverse.tier when a player finishes a tier. It holds the only key that can. |
| 🧾 Bureau | Works out credit levels from CityBank's public payment history, and writes com.dhaniverse.credit only for players who chose to show it. |
| 📒 Directory | At startup, finds our contracts by name (bank, market, foodhook and food.dhaniverse.eth). Refreshes every few minutes and keeps the last good answer. |
| 👂 Indexer | Reads our contracts' events for City Hall's price board and our logs. It can rebuild its records by replaying them. |
| 📤 Outbox and senders | Every chain write is first a database row: pre-flight check, send, retry, decoded errors. Refs mean nothing is ever bought twice. |
| 💵 USDC float | Keeps the food court, supplier and teller keys funded with plain USDC transfers, so no loop runs dry, and keeps gas topped up. |
| 🔑 Keys | Arc: admin (cold), food court, supplier, teller, Central Bank. Sepolia: ENS admin (cold), names, Academy, bureau. Plus one address per player, derived from one server secret. |
| 🎮 The rest of the game | Pocket coins, jobs, energy, homes, the Academy's lessons and the CPI. Rust and Postgres, no chain. |
| 🩺 dhv doctor and dhv why | Our two tools: one checks keys, roles, balances, today's limit and ENS records in one go; the other explains any error. |

## 5. Two speeds: what waits for the chain

| Moment | Examples | Wait |
|---|---|---|
| 🚶 Never touches the chain | Walking, jobs, energy, eating, pocket money, lessons, chat. | No wait |
| 🏦 Settles in about a second | Saving, withdrawing, paying a friend by name, taking a loan, a month closing at the bank. | About 1 second, behind the bank's animation |
| 🍽️ Batched behind the scenes | The food the city ate, bought in one trade every few minutes, and the supplier's sales. | Nobody waits; players never see it |
| 🪪 Names in the background | A new player's ENS name and records, and profile changes. | About a minute on Sepolia; the game shows the name at once |
| 📈 Read once a day | Yesterday's food price, which sets menu prices and the CPI's food part. | Read at the start of each city day |

### Getting a name (ENSv2 on Sepolia)

The first thing a new player does in the tutorial. The name is theirs at once; ENS catches up in about a minute.

| Step | When | Where | What happens |
|---|---|---|---|
| 1 | tutorial | Game | Penny: First, what should we call you? Sam types sam. |
| 2 | ~5 ms | Server | Checks the name is free, in our database and on ENS, and reserves it. The game uses it straight away. |
| 3 | ~15 s | Sepolia · First transaction | The names key registers sam.dhaniverse.eth in our registry. Sam's address owns it, it uses the players' resolver, and it can't be transferred. |
| 4 | ~30 s | Sepolia · Second transaction | One multicall writes the records: Sam's Arc address (for Arc's coin type and as the default for every EVM chain), avatar and description. |
| 5 | ~30 s | Sepolia · Third transaction | The Academy key writes com.dhaniverse.tier = 0. Later tiers are written the same way, and no other key can write them. |
| 6 | ~1 min | Sepolia | Sam's address sets sam.dhaniverse.eth as its primary name, so any app that looks up the address shows the name. |
| 7 | alongside | Server | The indexer reads the registry's events, and Sam's profile card is ready for other players. |

*If Sepolia is slow, nothing changes for Sam: the name shows from our database, and ENS catches up.*

### Paying a friend by name (ENS and the bank)

Names are how players find and pay each other. No 0x numbers anywhere.

| Step | When | Where | What happens |
|---|---|---|---|
| 1 | 0 ms | Game | Sam opens the phone, taps Pay, and types priya. |
| 2 | ~200 ms | Server | Resolves priya.dhaniverse.eth through ENS's Universal Resolver, asking for her address on Arc (Arc's coin type). Any ENS name with an Arc or default address works, not just ours. |
| 3 | ~250 ms | Game | Shows Priya's avatar and name from her ENS records. Sam confirms 50 coins. |
| 4 | < 1 s | Arc · One transaction | CityBank checks the teller key and the ref, moves 50 coins of savings from Sam's account to Priya's, and records Transferred. |
| 5 | ~1 s | Game | Sam's stamp turns ✓, and Priya gets a note that Sam sent her 50 coins. |
| 6 | alongside | Server | Receipts show names, not 0x numbers: a reverse lookup, checked forward, so a fake name can't appear. |

*If the name doesn't resolve, or points somewhere new since Sam last paid it, Sam sees that before confirming.*

### A month closes (The bank's rules run)

When a player's month bar fills, the bank does its monthly work by its own public rules.

| Step | When | Where | What happens |
|---|---|---|---|
| 1 | 20 min of play | Game | Sam's month bar fills up. Sam has savings and a scooter loan. |
| 2 | ~5 ms | Server | Sam turned on auto-pay, so the teller moves enough pocket money into Sam's savings to cover the EMI (one deposit). |
| 3 | < 1 s | Arc · One transaction | CityBank.closeMonth(Sam, month 7) checks it's exactly Sam's next month, then pays interest on savings at the public rate. |
| 4 | < 1 s | Arc · One transaction | If the Central Bank changed the rate since last month, it reprices the scooter loan the way Sam chose: pay more each month, or pay for longer. |
| 5 | < 1 s | Arc · One transaction | It collects the EMI from savings and records EmiPaid: the interest part, the principal part, and what's left. |
| 6 | alongside | Server | The indexer reads the events. If Sam chose to show a credit level, the bureau updates it on ENS. |
| 7 | ~1 s | Game | Sam's month cards, one at a time: earned, food, other spending, savings grew by 3, EMI paid ✓. |

*If savings are short, CityBank records a missed EMI instead of failing, and Penny explains the options. Three misses in a row are recorded as a default; the loan stays open, and collection carries on when savings allow.*

### Buying a chai (Players never wait)

The most common money action in the game. The player is done in milliseconds; the chain hears about it minutes later, as part of a batch.

| Step | When | Where | What happens |
|---|---|---|---|
| 1 | 0 ms | Game | Sam taps Buy at the chai stall. The drinking animation plays and the energy bar goes up by 10. |
| 2 | ~5 ms | Server | Takes 10 coins from Sam's wallet in our database and adds 1 FOOD to the current batch. Sam is done: nothing waits for the chain. |
| 3 | every few minutes | Server | The meal batcher closes the batch (say 140 FOOD from 60 meals across the city) and saves it as a to-send row with a new ref. |
| 4 | +50 ms | Server | Pre-flight: simulates the trade. If it would fail, the reason is logged and nothing is sent. |
| 5 | < 1 s | Arc · One transaction | FoodRouter checks the food court key's role and that the ref is new, reads today's limit from FoodHook, and asks Uniswap to buy up to 140 FOOD. |
| 6 | < 1 s | Arc · One transaction | Inside the trade, FoodHook checks it came through FoodRouter (noting the opening price if it's the day's first trade), then checks the new price is inside today's limit and adds the trade to today's totals. |
| 7 | < 1 s | Arc · One transaction | FoodRouter pays the USDC from the food court key, burns the 140 FOOD (it's been eaten) and records FoodBought: wanted 140, got 140. |
| 8 | alongside | Server | The indexer reads FoodBought and TradeCounted. City Hall's price board updates. |

*If the chain is slow or down, players notice nothing: the batch waits in the outbox, and menus keep today's prices.*

### A new food day (Menu prices)

How a day of eating and supplying becomes tomorrow's menu prices.

| Step | When | Where | What happens |
|---|---|---|---|
| 1 | all day | Server | The city supplier sells the day's arrivals in small slices through FoodRouter. Festivals and harvests change how much; when the Central Bank raises rates, it pushes prices less hard. |
| 2 | all day | Arc | Every buy and sell moves the price, always within 5% of the day's opening price and between 5 and 30 coins per FOOD. |
| 3 | midnight | Arc | A new day starts by the block clock. No transaction is needed: FoodHook counts the next trade toward the new day and notes its opening price. |
| 4 | +1 min | Server | The price reader calls dayPrice(yesterday): total USDC ÷ total FOOD. Say 10.20 coins, so the food index is 1.02. |
| 5 | +1 min | Server | Menus update from the index: chai stays 10 (10.2 rounds to 10), a burger goes from 45 to 46. The CPI takes the food index as its biggest part. |
| 6 | morning | Game | Players see the new prices with ▲▼ arrows. Tap one and Penny explains why. |

*A day with no trades has no price, so the server keeps the last one.*

### If a chain is down (The game keeps going)

Nothing a player does needs a chain to answer at once, so the game doesn't stop.

| Step | When | Where | What happens |
|---|---|---|---|
| 1 | always | Game | Walking, jobs, eating and lessons never touch a chain, so they keep working. |
| 2 | Arc down | Server | Menus keep the last food index. Bank actions and meal batches wait in the outbox, in order, and the bank shows confirming… |
| 3 | Sepolia down | Server | New names show from our database, and profiles use the last records we read. |
| 4 | back | Server | The outbox sends in order. Months close one at a time, so a backlog can't skip or repeat one. Merged meal batches stop at the day's 5% limit. |
| 5 | safety | Arc | Every action carries a ref that works once, so a retry can never pay, charge or buy twice. |

*If a contract itself breaks, we take its keys away, deploy a fixed one and repoint its ENS name. The server follows the name.*

## 6. When something breaks

### Find it in seconds

Example output of `dhv why`. The line numbers are placeholders until the code exists.

**A trade from a stranger**

```text
$ dhv why 0x3b9e…41c2
✗ FoodHook refused · FoodHook__NotRouter
  sender 0x7a1f…09bd · router 0x5c2e…a118
  Unwrapped  from Uniswap's WrappedError around our hook's refusal
  Meaning  Trades must come through FoodRouter. Someone tried the pool directly.
  Where    contracts/src/food/FoodHook.sol:88 · beforeSwap()
  Next     Harmless. Nothing traded.
```

**A key without the right role**

```text
$ dhv why 0x91d0…7f3a
✗ FoodRouter refused · FoodRouter__NotAllowed
  caller 0x44b2…c0de · has None · needs Buyer
  Meaning  This key isn't the food court key, or it was switched off.
  Where    contracts/src/food/FoodRouter.sol:64 · buyFood()
  Next     Check the server's key settings. dhv doctor lists every key's role.
```

**A month closed twice**

```text
$ dhv why 0x5e02…b7c1
✗ CityBank refused · CityBank__WrongMonth
  account sam.dhaniverse.eth (0x2f9a…44e0) · expected 8 · got 7
  Meaning  Month 7 is already closed. The retry was blocked, so no interest or EMI happened twice.
  Where    contracts/src/bank/CityBank.sol:142 · closeMonth()
  Next     Harmless. The outbox marks the row as done.
```

**The wrong key writing a credit level**

```text
$ dhv why --sepolia 0x77aa…0d3f
✗ ENS resolver refused · missing role
  key 0x91c4…e7b2 (names key) · record com.dhaniverse.credit · only the bureau key may write it
  Meaning  The names key tried to write a credit level, and ENS said no.
  Where    server/src/names/records.rs:57 · set_credit_level()
  Next     A bug on our server: credit writes must use the bureau key.
```

### Switch one piece off, and the rest keep working

FoodToken and FoodHook have no off switch: a Uniswap hook can't be changed, and a token shouldn't be. Everywhere else, taking a key's role away is the off switch, and every read keeps working.

| Switch off | What stops | What keeps working |
|---|---|---|
| FoodRouter: Food court key off | Meal batches reaching the chain | Everyone still eats; the game doesn't notice; Menus keep the last food index; The supplier keeps selling, so prices drift down (5% a day at most); Reading prices and history |
| FoodRouter: Both market keys off | All trading: food prices freeze | The whole game, on the last food index; The pool, its money and its history, readable by anyone |
| CityBank: Teller key off | Saving, withdrawing, paying by name, new loans, month closes | Every balance and loan, safe and readable; Pocket money and the whole game; Months wait and close later, one at a time, in order |
| CityBank: Central Bank key off | Rate changes | Everything else, at the current rate |
| NameResolver: Names key off | New ENS names and profile edits | Every existing name and record; New players play under their username from our database; Paying by name |
| NameResolver: Bureau key off | Credit levels updating | Everything else |

### Fix it without breaking anything

1. **Switch it off.** Take the key's role away, or stop the server sending. The game keeps running.
2. **Find it.** dhv why names the contract, the error, the numbers and the line.
3. **Prove it.** Write a test that fails because of the bug. Now the bug can never quietly come back.
4. **Fix it.** Change the code until that test and every other test pass.
5. **Try it on a test world first.** Deploy the fix to a fresh test world and replay the last days of trades.
6. **Swap it in.** Deploy the fixed contract and point its ENS name at it (bank.dhaniverse.eth or market.dhaniverse.eth); the server follows the name. FoodRouter swaps without touching the pool or its history. A new CityBank is rebuilt from the old one's public records: the server re-deposits each balance and reopens each loan with what's left to pay. A FoodHook bug means a new hook and pool; the server carries the price history over.
7. **Switch back on and write it down.** Give the keys their roles back. The changelog says what broke and why, and you approve it.

## 7. Phases, bottom to top

Each phase runs the loop in §2 and ends with something you can run yourself. Sizes are relative (S, M, L).

The phases build bottom to top, on a repository everyone can read. Three people can work side by side (market, bank, names). Hours are rough until we re-cost them with the team.

### Before the first phase

- Accounts: Arc Studio, faucets and RPC keys.
- Test funds: about 50 Arc testnet USDC, 0.5 Sepolia ETH, and Sepolia test USDC for the dhaniverse.eth fee.
- Throwaway drills on toys, not Dhaniverse: a v4 hook with a day limit on Arc testnet; an ENSv2 name on Sepolia with a text record only one key may write; alloy resolving a name to Arc's coin type.
- Reading: Uniswap v4 hooks, ENSv2's Permissioned Registry and Resolver, Arc's EVM differences.
- Delete the drill code afterwards.

| # | Phase | Layer | Chapter | Size | Side by side |
|---|---|---|---|---|---|
| 0 | Setup: project, tools and rules | Layer 0 |  | S | Hours 0–2. Everyone. |
| 1 | Food token and price rules | Layer 1 | Food court | M | Hours 2–8. Market person. |
| 2 | The door: FoodRouter | Layer 2 | Food court | M | Hours 8–13. Market person. |
| 3 | The bank: CityBank | Layer 3 | Bank | L | Hours 2–14. Bank person, alongside Phases 1 and 2. |
| 4 | Names on ENSv2 | Layer 4 | Tutorial · profiles | M | Hours 0–14. Names person, alongside Phases 1–3. |
| 5 | Live on Arc testnet and Sepolia | Layer 4 |  | M | Hours 14–20. |
| 6 | Hand-off to the server | Off-chain |  | S | Hours 12–30, alongside Phase 5. |

### Phase 0: Setup: project, tools and rules

**Builds:** The public repository and the Arc Studio project; Foundry with pinned versions (Solidity 0.8.26, OpenZeppelin 5, Uniswap v4); Test kit: fake USDC at Arc's address, a local Uniswap pool, a Sepolia fork for ENS, named test keys; dhv why, the error catalog, and CI (build, tests, lint, the spec check).

**You'll see:** A test that fails on purpose prints: CityBank refused · CityBank__WrongMonth (expected 8, got 7) · CityBank.sol:142.

**Done when:**

- CI is green on an empty project
- dhv why decodes our errors, OpenZeppelin's, Uniswap's wrapped ones and ENS's
- Every public function has a plain-English line in this spec, or CI fails

**Arc Studio:** Create the Studio app. One test turn: can it deploy a contract at a mined address?

**Note:** Hours 0–2. Everyone.

### Phase 1: Food token and price rules

**Builds:** FoodToken; FoodHook; Tests on a local pool, at both token orders.

**You'll see:** On a local pool: a buy that would push the price up 6% stops at 5%, a stranger's trade is refused, and a day's trades give the right day price.

**Done when:**

- Every refusal tested
- The day price matches the worked example in the numbers
- The floor (5) and ceiling (30) hold at both token orders

**Arc Studio:** Second opinion on FoodToken and FoodHook.

**Note:** Hours 2–8. Market person.

### Phase 2: The door: FoodRouter

**Builds:** FoodRouter: buy, sell, liquidity, roles, refs; Burning eaten FOOD; Stopping at the day's limit instead of failing.

**You'll see:** The food court key buys a batch and the FOOD is burned. A batch sent twice is refused. At the limit, a batch buys what fits and says how much.

**Done when:**

- Every role and ref rule tested
- Buy, sell, add and remove stock work end to end on a local pool
- A replaced router takes over without moving the pool

**Arc Studio:** Second opinion on FoodRouter.

**Note:** Hours 8–13. Market person.

### Phase 3: The bank: CityBank

**Builds:** Savings, interest, deposits, withdrawals and transfers; Loans: the EMI maths, month closes, repricing, missed EMIs; The rate and its limits; The one-at-a-time rule.

**You'll see:** The plan's loan numbers come out exactly: 305.62, then 317.0 or 266 full payments after a 0.50% rise. A month closed twice is refused; a second loan too early is refused.

**Done when:**

- Every number in the bank's list hit exactly
- Every refusal tested
- A full year of one player's months run in a test, with a rate change in the middle

**Arc Studio:** Second opinion on CityBank.

**Note:** Hours 2–14. Bank person, alongside Phases 1 and 2.

### Phase 4: Names on ENSv2

**Builds:** dhaniverse.eth registered; Our registry and two resolvers, through ENS's factory; ENSv2 roles for the names, Academy and bureau keys; The server's name registrar, primary names and paying by name; The city's directory: bank, market, foodhook, food.

**You'll see:** A new player gets a name in under a minute. Any ENS app shows sam.dhaniverse.eth with Sam's Arc address and Academy tier. The names key trying to write a credit level is refused by ENS.

**Done when:**

- Every write reads the resolver and token fresh; nothing is hard-coded
- Paying by name works with a judge's own ENS name, not just ours
- Primary names check out both ways

**Note:** Hours 0–14. Names person, alongside Phases 1–3.

### Phase 5: Live on Arc testnet and Sepolia

**Builds:** Mine FoodHook's address, deploy all four contracts; The FOOD/USDC pool and its stock; the bank's reserve; Keys and roles on both chains; The city's directory names pointed at the real contracts.

**You'll see:** One scripted city day on the real chains: meals bought in batches, a month closed, a payment by name, and a new player's name, all visible on the explorers.

**Done when:**

- Gas per action measured on both chains
- dhv doctor checks the whole live setup in one go

**Arc Studio:** Deploy FoodToken, FoodRouter and CityBank through Studio if the Studio test turn passed. FoodHook probably goes through Foundry, because of its mined address.

**Note:** Hours 14–20.

### Phase 6: Hand-off to the server

**Builds:** ABIs and typed Rust bindings; The error catalog for dhv why; Example meal batcher, supplier, price reader, teller, name registrar and directory.

**You'll see:** Your teammate's server plays a full city day through our kit.

**Done when:**

- The server runs one scripted city day end to end
- Every error the server can hit has a plain-English line

**Note:** Hours 12–30, alongside Phase 5.

## 8. Decisions I've made for you

Each is my pick. Say no to any and the map changes.

1. **Where does the code live?** ✓ A public GitHub repository for the product code and its technical documentation.
   - *Why:* Arc Studio can only pull a public repo, and the code, its tests and this map are readable and runnable by anyone.
   - *Instead:* Keep the repository private.
2. **What goes on-chain?** ✓ Three things: the food market (Uniswap), the bank (CityBank) and player names (ENSv2).
   - *Why:* Each earns its place: players gain from rules nobody can quietly change. Arc's finance surfaces call for lending, borrowing and credit, which is the bank; Uniswap v4 gives the food market its pool and hook; ENSv2 keeps every name and record real.
   - *Instead:* The food market only (v2): smaller, with no bank on-chain.
3. **Do players have wallets?** ✓ Each player gets an Arc address whose key our server holds. It's their bank account number and what their name points to.
   - *Why:* No wallet app, no gas, no pop-ups. The address is real, so their name, savings and history are real on-chain.
   - *Instead:* Player-held wallets (for example Circle Wallets) later, once players want to take their money and name with them.
4. **How do names work?** ✓ Every player gets a real ENSv2 name on Sepolia, like sam.dhaniverse.eth. It's how they appear and get paid, and it carries their avatar and Academy tier.
   - *Why:* ENSv2 is used for real, not as decoration: our own registry for the city, names that can't be sold or taken, records for Arc's coin type, primary names, and per-record roles. Our server finds its own contracts by name, so nothing is hard-coded.
   - *Instead:* Offchain names through a CCIP-Read gateway: free and instant, but they skip ENSv2's registry and roles.
5. **Who writes what in ENS?** ✓ Three keys with one ENSv2 role each: names (address, avatar), Academy (tier only), bureau (credit level only, and only for players who opt in). The city's own names sit on a second resolver only the admin can write.
   - *Why:* ENSv2 roles limit a key to one record type, but not to one name. The separate resolver means a leaked names key can't point bank.dhaniverse.eth somewhere else.
   - *Instead:* One key for everything: simpler, but one leak rewrites every record.
6. **How much of the bank's maths runs on-chain?** ✓ All of it. CityBank works out interest and EMIs from the public rate. The server only says a player's month has ended, and months go forward one at a time.
   - *Why:* Nobody, us included, can quietly change a loan or skip a month.
   - *Instead:* The server computes and CityBank only records the numbers (v1's TownBank): less contract code, a weaker promise.
7. **Is 'one commitment at a time' a contract rule?** ✓ Yes. One open loan per player; a second only after three on-time EMIs and no misses.
   - *Why:* It's rule 4 of the game design, enforced where no server bug can get round it.
   - *Instead:* A server-only rule.
8. **How do the market's days and limits work?** ✓ FoodHook counts days from the block clock, and a trade stops at the 5% limit instead of failing.
   - *Why:* No day-end transaction to forget, and a busy evening never makes a transaction fail.
   - *Instead:* The server starts each day (setDay), and over-limit batches fail and retry smaller.
9. **How do we fix a broken contract?** ✓ No upgrades: we replace it and repoint its ENS name.
   - *Why:* No proxies means less code and nothing to misconfigure, and the bank's rules can't be changed behind a player's back. Uniswap hooks can't be upgraded anyway.
   - *Instead:* Upgradeable contracts (UUPS proxies): fixes in place, but the rules could change after you sign.
10. **Which compiler?** ✓ Solidity 0.8.26, the version Uniswap v4 is built with.
   - *Why:* The market compiles with the exact code it talks to. Its known bugs only affect patterns we don't use (we don't use via-IR).
   - *Instead:* 0.8.37: newer, with fewer known bugs, but Uniswap's test code would need a separate build.

### Considered, and kept off-chain

| What | Why it stays off-chain |
|---|---|
| Wages and every shop purchase | Thousands of tiny payments nobody needs to check. Meals still reach the chain, added up, through the food market. |
| Pocket money | It changes every few seconds. It goes on-chain when a player saves it at the bank. |
| Homes as NFT deeds | Homes come late (Academy tier 5), and the home loan is already in CityBank. A deed can come later. |
| Academy badges as tokens | An ENS record that only the Academy can write does the same job, with no new contract. |
| The CPI and the Central Bank's AI votes | Worked out on our server. The decision lands on-chain with each rate change: the rate, the CPI and a fingerprint of the report. |
| Energy, and what each player eats | Game state. The city's total demand reaches the chain as batch buys. |
| Players trading FOOD themselves | Optional later (Academy tier 6). Prices move without it. |
| The game clock | The server's. The chain only sees months moving forward one at a time, and food days from the block clock. |

## 9. Arc Studio: where it fits

| Where | How | Fits? |
|---|---|---|
| Project home | Create the Studio app, then pull the repository into it. | ✓ Easy |
| A second check on every phase | Once our tests pass, Studio reviews that phase's contracts. It's an AI review, not a formal audit. | ✓ Easy |
| Deploys | FoodToken, FoodRouter and CityBank deploy through Studio, so anyone sees them there. | ? Check at launch |
| FoodHook | It must sit at a mined address. Studio may not support that; Foundry can. | ? Check at launch |
| A public page | Studio builds a small page on our contracts: today's food price and the bank's rates. | ✓ Easy |
| Testnet USDC | Studio's faucet covers the few USDC the pool and gas need. | ✓ Easy |
| ENS on Sepolia | Studio works on Arc only, so the ENS setup goes through Foundry scripts. | ✗ No |
| Day-to-day coding | A Studio deploy takes 5–20 minutes and usage is capped. Local tests take seconds. | ✗ No |
| The game and the Rust server | Studio runs only contracts and web pages. | ✗ No |

## 10. Rules of the code

1. **One contract, one job.** A contract does one thing. A second job gets a second contract.
2. **Names say what they do.** Contracts are nouns (FoodRouter), functions are verbs (buyFood), events are past tense (FoodBought), errors name the contract and the problem (FoodRouter__RefUsed).
3. **Every error carries its numbers.** Not just 'too much', but how much and what the limit was.
4. **Every change emits an event.** Each state change emits an event with the day number, so the market's history can be replayed.
5. **Money is whole cents.** 1 coin = 100 cents = 0.0001 USDC, and one cent is exactly one USDC base unit, so there are no fractions. FOOD also has 6 decimals.
6. **Check, then change, then pay.** Checks first, then update the records, and only then move money (checks-effects-interactions).
7. **Reading is never blocked.** Every read function works even when every key is switched off.
8. **Every action has a ref, and a ref works once.** That's how a retry can never pay, charge or buy twice.
9. **No chains between our contracts.** Our contracts don't call each other. The only links are Uniswap's own path (FoodRouter → PoolManager → FoodHook) and FoodRouter burning the FOOD it just bought. CityBank talks only to USDC.
10. **Names, not addresses.** The server finds our contracts and players by ENS name. The only fixed entry point is ENS's own, which the alloy library already knows.
11. **Months only go forward.** CityBank closes a player's months one at a time, in order. Nothing can be skipped or done twice.
12. **Money rules are tested first.** Every bug becomes a test before it's fixed.
13. **The spec and the code can't drift.** CI fails if a public function has no plain-English line here.
14. **No magic numbers.** Every number is a named constant with its unit in the name.

## 11. Numbers the tests must hit

| What | Number | Phase |
|---|---|---|
| Base FOOD price | 10 coins (0.001 USDC) per FOOD. A chai uses 1 FOOD, a burger 4.5, a restaurant meal 8 | 1 |
| Floor and ceiling | 5 and 30 coins per FOOD (half and three times the base) | 1 |
| Day limit | 5% either way from the day's opening price, at either token order. A city day is one real hour (founder, 28 Oct); test worlds can use minutes | 1 |
| Pool fee | None: only our own two keys trade, so a fee would only move coins between our own pockets (founder, 28 Oct) | 1 |
| Day price | 1,010 coins for 100 FOOD + 520 coins for 50 FOOD → 1,530 ÷ 150 = 10.20 coins → food index 1.02 | 1 |
| Pool depth | In tests the pool holds ~5,000 FOOD and 5 USDC, where ~120 FOOD moves the price the full 5%. The live pool's size must match the city's real demand: set it in Phase 5 | 2, 5 |
| A batch at the limit | Buys what fits, reports the rest, never fails | 2 |
| Rates at the Central Bank's 5.50% | Savings 3.50% · scooter loan 14.20% · home loan 8.20% | 3 |
| Savings interest | 1,000 coins at 3.50% → 2.91 coins a month (rounded down to the cent) | 3 |
| Scooter loan | 1,200 coins over 12 months at 14.20% → EMI 107.86 coins | 3 |
| Home loan | 36,000 coins over 240 months at 8.20% → EMI 305.62 (305.615, rounded up to the cent) | 3 |
| If the rate rises 0.50% before the first EMI | Keep the length → EMI 317.0 · keep the EMI → 266 full payments and a smaller last one | 3 |
| Rate limits | At most 0.50% per decision, between 0% and 15% | 3 |
| One at a time | A second loan is refused until the first has 3 on-time EMIs and no misses. Savings are never lent: the bank lends only its own reserve | 3 |
| Arc's ENS coin type | 2152525650 (0x80000000 OR Arc's chain id 5042002) | 4 |
| A ref | Works once; a second send is refused | 2, 3 |
| Menus at index 1.02 | chai 10.2 → 10; burger 45.9 → 46 (the server rounds half up) | 6 |
| Gas | Arc: roughly 0.005 USDC a trade at 25 gwei. Sepolia: a few hundred thousand gas per new player. Both measured for real in Phase 5 | 5 |

## 12. Words

| Word | Plain meaning | Like |
|---|---|---|
| Contract | A program that lives on the chain and follows fixed rules. |  |
| Function | One thing a contract can do. |  |
| Transaction | Pressing a function for real. Costs a little gas, and is final in under a second on Arc. |  |
| Read (view) | Looking something up. Free, instant, and never blocked. |  |
| Event | A record a contract writes when something changes. |  |
| Error (revert) | The contract refuses, says why, and nothing changes. |  |
| Key | A secret that signs transactions. The server holds a few, each with one job, plus one per player. |  |
| Account | A player's bank account: an Arc address whose key our server holds. | A bank account number |
| EMI | The fixed monthly payment on a loan: part interest, part paying it off. |  |
| The rate | The Central Bank's rate. Savings earn it minus 2%; loans cost it plus their product's spread. | The RBI's repo rate |
| Role | Which FoodRouter functions a key may press: Buyer, Seller or None. |  |
| Ref | A reference number on every trade. It works once. | A UPI transaction ID |
| Token | A list of balances on the chain. FOOD and USDC are both tokens. |  |
| Burn | Destroying tokens for good. Eaten FOOD is burned. |  |
| Pool | Uniswap's shared pot of FOOD and USDC. Trades against it set the price. |  |
| Liquidity (stock) | What's in the pool. More stock means each trade moves the price less. |  |
| Hook | Our rules that run inside every Uniswap trade. |  |
| Router | The contract you trade through. Ours is the only door into the pool. |  |
| Day limit | How far the price may move in one city day: 5% either way from the day's opening price. | A stock exchange's circuit breaker |
| Food index | Yesterday's food price divided by the base price (10 coins). Menu prices are base prices times this. |  |
| Batch | Many meals added up into one trade. |  |
| Outbox | The server's to-send list. Nothing is lost if the chain is slow. |  |
| Indexer | The server's reader that turns events into records. |  |
| Gas | The small USDC fee per transaction. The server pays it. |  |
| Finality | When a transaction can't be undone. On Arc, as soon as it's in a block (under a second). |  |
| Mined address | A Uniswap hook's address must carry its permissions in its last digits, so we search for a deploy setting that produces one. |  |
| Arc Studio | Circle's AI builder. It reviews, deploys, and builds web pages on Arc testnet. |  |
| ENS name | A readable name, like sam.dhaniverse.eth, that points to addresses and holds profile records. | A UPI ID |
| Registry | ENS's list of who owns which name. dhaniverse.eth has its own. |  |
| Resolver | Where a name's records live: its addresses, avatar and other text. |  |
| Record | One piece of a name's profile, such as its Arc address or its Academy tier. |  |
| Coin type | The number that says which chain an address record is for. Arc's is 2152525650. |  |
| Primary name | The name an address chooses to show. It must point back to the address to count. |  |
| Universal Resolver | ENS's single entry point for reading any name. |  |
| Sepolia | Ethereum's test network, where ENSv2 lives. |  |

## 13. Checked on 5 Nov

- Arc testnet's RPC is rpc.testnet.arc.io, chain id 5042002 (read on chain again 28 Oct). ([source](https://docs.arc.io/arc/references/rpc-endpoints.md))
- Uniswap's PoolManager at 0x8366a39C…0951 has code on Arc testnet: 24,009 bytes (read on chain 28 Oct).
- USDC's ERC-20 view at 0x3600…0000 has 6 decimals (read on chain 28 Oct). ([source](https://docs.arc.io/arc/references/contract-addresses.md))
- The gas price read 25 gwei on 28 Oct. Transactions under 20 gwei are dropped silently, block timestamps can repeat, and a transaction is final once it's in a block. ([source](https://docs.arc.io/arc/references/evm-differences.md))
- ENSv2 is live on Sepolia. Each name is an ERC-1155 token with role-based permissions, and subnames are created with register() on the parent name's registry. ([source](https://docs.ens.domains/ensv2/permissioned-registry/))
- ENSv2's Permissioned Resolver limits a key's role to one record type (for example one text key), but not to one name. Names that need different writers need separate resolvers. ([source](https://docs.ens.domains/ensv2/permissioned-resolver/))
- Apps must use the Universal Resolver, pass a coin type for each chain, and not hard-code resolver addresses or cache token IDs. alloy-rs 2.4.2 and later support ENSv2. Registering a .eth name is paid in a stablecoin. ([source](https://docs.ens.domains/web/ensv2-readiness/))
- A primary name needs both directions: the address's reverse record, and the name's address on that chain. A default reverse record on Ethereum covers every EVM chain. ([source](https://docs.ens.domains/web/reverse/))
- Solidity 0.8.26's known bugs: three need via-IR (we don't use it); the other three are low or low-to-medium and avoidable. ([source](https://github.com/ethereum/solidity/blob/develop/docs/bugs_by_version.json))
- Arc Studio writes, reviews and deploys to testnet, builds front ends on existing contracts, and exports to GitHub. Deploy turns take 5–20 minutes. ([source](https://docs.arc.io/ai/arc-studio-cli.md))
