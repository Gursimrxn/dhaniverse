# Dhaniverse server protocol, version 3

How the Godot client talks to the Rust server. **The server decides what happened, and the client shows it.** The
client never works out a price, an amount or a reward: it shows the last `you` and `city` it was sent.

Version 3 is Dhaniverse: USDC is the only money. Meals are bought on chain at the live food price, quests cost energy and
pay USDC, the house pays chests, the Rush pot, errands and rescue meals, sponsors pay their quests, and nothing is paid
out without the Town Pass. Version 2's messages are all still here, with the changes marked **v3**.

- WebSocket, one JSON object per text message, at `ws://127.0.0.1:7878` by default. Plain HTTP on the same port is in
  [HTTP](#http).
- Every message has a `"type"`. Unknown fields may appear in later versions, so ignore them.
- **Money** is USDC in base units: `1000000` is 1 USDC, `4000` is 0.004 USDC. Always show it as USDC with a dollar sign.
- **FOOD** is in base units (`1000000` is 1 FOOD). **Indexes** are basis points (`10200` is 1.02).
- **Times** are milliseconds. Two clocks: `day`/`day_ms` is the **city day**, the food market's, one real hour; every
  `*_at` field (`ready_at`, `ends_at`, `next_at`…) is on the **real clock**, `city.now_ms`, ms since the city began,
  where a real day is `city.real_day_ms` (24 hours). Campaign `starts`/`ends` are the chain's unix **seconds**.
- All numbers are whole and fit a GDScript `float` exactly, so cast them with `int()`. Quest token amounts can be bigger
  than that, so they are never sent to the client.

## Connecting and resuming

Send `hello` first. Any other message before it gets an `error`.

```json
{"type": "hello", "protocol": 3, "player": "sam", "secret": "9f3c1e7a0b5d4c2e8a6f1d3b7c9e0a42"}
```

This is also how you resume: say the same name and secret again. A `protocol` other than 3 gets an `error`. The reply is
always one `snapshot`, or a `hello_refused`.

```json
{"type": "snapshot", "seq": 41, "debug": false, "you": {...}, "city": {...}, "feed": [...]}
```

- A snapshot is the whole truth, so replace everything you hold. Send `hello` again after any drop.
- A second connection under the same name takes over, and the older one gets `{"type": "kicked"}` and is closed.
- Logging off walks you away from the stall: a Rush run under way ends, and still counts.
- A new player gets a wallet from the chain when they arrive. Offline it's in the snapshot; on a chain, `wallet` is
  `null` until a `WalletReady` event, a few seconds later.

### `you`

```json
{
  "name": "sam",
  "title": "Regular",
  "energy": 64,
  "energy_max": 100,
  "energy_regen_at": 245000,
  "in_rush": false,
  "served": 0,
  "rush_ends_at": null,
  "runs_left": 3,
  "best_run": 12,
  "best_today": 12,
  "firsts": [{"first": "first_meal", "carved": false}],
  "following": [],
  "ranks": {"rush": 1},
  "best_board": "rush",
  "neighbours": {"rush": []},
  "wallet": "0x2dde4583f88d88eff86ed67ca50801ca4fc19777",
  "usdc": 700000,
  "human": true,
  "ens": "sam.tallyport.eth",
  "sign": "Sam's chai",
  "quests": [],
  "errands_left": 3,
  "mystery_left": 1,
  "grandma_done": false,
  "chest": {"ready_at": 0, "tier": "brass", "pity": 3, "pity_every": 10, "weekly_ready_at": 0},
  "streak": {"days": 3, "week_days": 3, "need": 5},
  "tickets": 7,
  "vouchers": 1,
  "pending": 0,
  "pending_rewards": [],
  "meal_pending": null,
  "free_meal_at": 86400000,
  "rescue_at": null,
  "price_call": {"day": 4, "call": "up"},
  "titles": ["Spice Runner"],
  "stamps": ["spice-run"],
  "referrer": null
}
```

| Field | Meaning |
|---|---|
| `title` | What everyone sees: the latest title earned (`Spice Runner`, `Steady Hand`, `Grandma's Heir`), else `Regular` after a first, else `Newcomer` |
| `energy` | 0 to `energy_max` (100), right now, including what came back by itself |
| `energy_regen_at` | Below 40, energy comes back one point every 4 minutes: when the next point arrives, on the real clock. `null` at 40 or more. The server also sends a fresh `you` when it arrives |
| `in_rush`, `served`, `rush_ends_at` | A Rush run under way, its orders so far, and when the server ends it (real clock). `served` is the last run's after it ends |
| `runs_left` | Free Rush runs left today (3 a real day) |
| `best_run` | Your best run this season (the `rush` board). `best_today` is today's best, which is what the Rush pot ranks |
| `wallet` | Your wallet address on chain, or `null` before the chain gave you one |
| `usdc` | Your wallet's USDC balance as the chain last reported it, or `null` before it has |
| `human` | Whether you hold the Town Pass (World ID). Payouts need it |
| `ens` | Your name, such as `sam.tallyport.eth`, registered when you get the Town Pass. `null` before |
| `sign` | Your shop sign, your name's `description` record |
| `quests` | Quests you're on, with their steps. See [quests](#quests) |
| `errands_left`, `mystery_left` | Errands and mysteries you may still take today |
| `grandma_done` | Whether you opened Grandma's strongbox this season |
| `chest` | The daily chest: `ready_at` (0 or past `city.now_ms` means ready), the `tier` it will be (`wood`, `brass`, `gold`), `pity` (chests since your last golden drop; at `pity_every` one is guaranteed) and when the weekly chest may next open |
| `streak` | `days` in a row you came, and `week_days` you came in the last 7 (the weekly chest needs `need`, 5) |
| `tickets` | Your tickets for this week's draw |
| `vouchers` | Meal vouchers from chests, to spend with `BuyMeal` |
| `pending` | USDC owed to you and not yet paid: waiting for your Town Pass, or for tomorrow's budget. `pending_rewards` lists each: `{"ref", "amount", "why", "waiting"}`, `waiting` being `town_pass`, `budget` or `chain` |
| `meal_pending` | The ref of a meal on its way to the chain, or `null`. Show a pending stamp |
| `free_meal_at` | When the free thali is ready again (0 or past means now) |
| `rescue_at` | When a neighbour arrives with a thali, if one is on the way |
| `price_call` | Your Price Call for today, or `null` |
| `titles`, `stamps` | What you've earned. Stamps are also written on your ENS name |
| `referrer` | Who you said sent you |
| `following`, `ranks`, `best_board`, `neighbours` | See [the feed, the boards and profiles](#the-feed-the-boards-and-profiles) |

### `city`

Town-wide numbers only. Nothing in `city` is about one player, except names and titles on the boards.

```json
{
  "day": 3,
  "day_ms": 3600000,
  "day_elapsed_ms": 120000,
  "now_ms": 10920000,
  "real_day": 0,
  "real_day_ms": 86400000,
  "next_real_day_at": 86400000,
  "chain": "offline",
  "price": 4121,
  "open_price": 4000,
  "food_index_bps": 10200,
  "menu": [{"name": "chai", "food": 1000000, "price": 4121, "max_usdc": 4204, "was": 4080, "energy": 10}],
  "food": {"price": 4121, "floor": 2000, "ceiling": 8000, "meals_today": 12, "usdc_today": 96000},
  "free_meal_energy": 40,
  "rush": {"run_ms": 90000, "runs_per_day": 3, "most_orders": 40, "pot": 1200000, "today": [{"rank": 1, "name": "sam", "title": "Regular"}]},
  "most_orders_per_run": 40,
  "errands": {"rate": 40000, "per_day": 3, "energy": 10, "list": [{"quest": "errand:chai_round", "title": "The Chai Round", "story": "..."}]},
  "mystery": {"quest": "mystery:night_bell", "title": "The Night Bell", "story": "...", "energy": 50, "payout": 500000, "boosted_by": null},
  "grandma": {"quest": "grandma", "title": "Grandma's Ledger", "story": "...", "energy": 50},
  "golden_drop": 50000,
  "bounty": [{"id": 1, "quest": "campaign:1", "kind": "sponsored", "sponsor": "0x8ba1…", "title": "The Spice Run", "template": "spice_run", "payout": 1000000, "energy": 30, "slots": 50, "slots_left": 47, "claims": 3, "humans": 3, "budget": 45000000, "spendable": 45000000, "paid": 3000000, "remaining": 42000000, "daily_cap": 6000000, "starts": 1793921395, "ends": 1794526195, "status": "live", "swarm": null}],
  "house": {"budget_bps": 400, "seen": true, "fixed": {"balance": 100000000, "budget": 4000000, "spent": 0, "budget_left": 4000000, "available": 4000000}, "surprise": {...}, "safety": {...}, "paid_today": 0, "rescue_meals": {"today": 0, "total": 0, "usdc_total": 0}, "draw_reserved": 0},
  "treasury": {"balance": 3900, "revenue_today": 3900, "harvest_today": 3900, "revenue_total": 3900, "split": {"fixed": 0, "safety": 0, "ops": 0, "team": 0}, "split_bps": {"fixed": 6000, "safety": 1000, "ops": 2000, "team": 1000}, "last_split_at": 0},
  "float": {"total": 0, "liquid": 0, "invested": 0, "buffer": 0, "daily_caps_sum": 9000000, "liabilities": 0, "yield_earned": 0, "loss_reserve": 0},
  "town_goal": {"week": 0, "target": 200, "progress": 12, "reached": false},
  "draw": {"week": 0, "tickets": 31, "prize": 5000000},
  "shock": "festival",
  "paper": {"day": 3, "headline": "A festival brings a crowd to town", "stories": ["..."]},
  "resident_walk_ms": 25000,
  "emotes": ["clap", "laugh", "wow", "sad"],
  "boards": {"rush": [{"rank": 1, "name": "sam", "title": "Regular"}]},
  "season": {"number": 1, "shock": "", "ends_day": 168}
}
```

- `chain` is `offline`, `anvil` or `sepolia`. Offline, the money is a rehearsal: say so on screen.
- `price` is the live food price in USDC base units per FOOD. It moves with every meal anyone buys and every harvest
  Kofi sells, inside a floor and a ceiling. `open_price` is 0 before the day's first trade.
- **v3:** a menu `price` is that meal's FOOD at the live price, rounded up. `max_usdc` is the most the meal ticket allows
  (2% over, for the price moving before it's eaten); the meal costs `price` or a little more, never over `max_usdc`.
  `was` is what it cost at yesterday's average price, for an arrow on the tag.
- `food` is the town's food today: meals eaten and the USDC spent on them, as totals.
- `rush.pot` is today's Rush pot so far (30% of the FIXED bucket's day budget), split at the real day's close among
  `rush.today`'s top 10.
- `errands.rate` is what an errand pays today. `mystery` is today's mystery quest; `boosted_by` is the campaign paying
  for it, if one is. `grandma` is offered until it's done this season.
- `bounty` is every campaign the chain has told us about. Show the ones with `status` `live` on the Bounty Board, and
  take them with their `quest`. `kind` is `sponsored` (a card) or `boosted` (it pays for the mystery instead). `status` is
  `live`, `full`, `upcoming`, `ended` or `closed`. `swarm` is the Swarm reference of the campaign's story and image, or
  `null`; the richer card comes from `GET /arkiv/campaigns`.
- `house` is HousePool's three buckets as the chain last reported them: `balance`, today's whole `budget` (4% of the
  balance at the day's start), what's `spent` today, `budget_left`, and what's `available` to promise now. `seen` is
  false until the chain has reported the pool at all; until then nothing is paid. `treasury` and `float` are the
  Treasury's food revenue and split, and FloatManager's books, for the dashboard.
- `town_goal` is this week's meals town-wide against the target. Reaching it makes everyone's next chest one tier
  better. `draw` is this week's draw: tickets held by people with the Town Pass, and the prize it would have now.
- `shock` is `"festival"`, `"harvest"`, `"drought"` or `""`. `paper` is `null` before the first morning paper.

## Sending a command

```json
{"type": "command", "ref": "sam-0042", "command": {"type": "ServeOrder"}}
```

Make a new `ref` for each thing the player actually did, and **keep the same `ref` when you retry it**. A ref works once,
so a retry can't count twice. Every command gets exactly one `result`, after the events it caused.

```json
{"type": "result", "ref": "sam-0042", "ok": true}
{"type": "result", "ref": "sam-0042", "ok": false, "refusal": {"type": "RushFull", "most": 40}}
```

A refusal changes nothing. On a retry after a dropped connection, `RefUsed` means the first try got through. Commands
that send something to the chain (`BuyMeal`, `Swap`, `Deliver`, the cargo step) carry their ref there: a new attempt
after a `MealFailed` or `QuestStepFailed` needs a new ref.

| Command | Fields | Refused with |
|---|---|---|
| `StartRush` | | `AlreadyInRush`, `NoRunsLeft` |
| `ServeOrder` | | `NotInRush`, `RushOver`, `RushFull`, `RefUsed` |
| `EndRush` | | `NotInRush` |
| **v3** `FreeMeal` | | `FreeMealNotReady`, `EnergyFull` |
| **v3** `BuyMeal` | `item`, and `voucher: true` to spend a meal voucher | `UnknownItem`, `EnergyFull`, `MealPending`, `NoWallet`, `NotEnoughUsdc`, `NoVoucher`, `NeedsTownPass`, `BudgetSpent`, `RefUsed` |
| **v3** `OpenChest` | `weekly: true` for the weekly chest | `ChestNotReady`, `WeeklyChestNotReady` |
| **v3** `TakeQuest` | `quest` | `UnknownQuest`, `AlreadyOnQuest`, `NotEnoughEnergy`, `NoErrandsLeft`, `NoMysteryLeft`, `QuestDoneBefore`, `CampaignClosed`, `NoSlotsLeft`, `PerHumanCap` |
| **v3** `QuestStep` | `quest`, `step` | `NotOnQuest`, `WrongStep`, `StepWaiting`, `NotAShockDay`, `NoWallet`, `NeedsTownPass`, `NotEnoughUsdc` |
| **v3** `AbandonQuest` | `quest` | `NotOnQuest`, `StepWaiting` |
| **v3** `QuoteSwap` | `quest` | `NotOnQuest`, `WrongStep`, `StepWaiting`, `QuoteTooSoon` |
| **v3** `Swap` | `quest` | `NotOnQuest`, `WrongStep`, `StepWaiting`, `NoWallet`, `NotEnoughUsdc`, `QuoteStale`, `RefUsed` |
| **v3** `Deliver` | `quest` | `NotOnQuest`, `WrongStep`, `StepWaiting`, `RefUsed` |
| **v3** `PaintSign` | `text`, 1 to 80 characters, one line | `BadSign`, `NoName` |
| **v3** `PriceCall` | `call`: `"up"`, `"flat"` or `"down"` | `AlreadyCalled` |
| **v3** `TownPass` | | `AlreadyHuman`, `NoWallet`. Its result carries a `url` |
| **v3** `Refer` | `player`: who sent you | `ReferringYourself`, `UnknownPlayer`, `AlreadyReferred`, `TooLateToRefer` |
| `CarveFirst` | `first` | `NotEarned`, `AlreadyCarved` |
| `AskMentor` | `question`, up to 200 characters | `UnknownPlayer`, `QuestionTooLong` |
| `React` | `post`, `emote` | `UnknownPost`, `UnknownEmote`, `AlreadyReacted`, `UnknownPlayer` |
| `Follow` | `player` | `UnknownPlayer`, `FollowingYourself` |
| `Unfollow` | `player` | `NotFollowing` |
| `ClaimName` | `name` | see [names](#names-secrets-and-other-people) |

The chain, the clock, the market, the paper and the feed are the server's, and a client can't send them. A message
with a command that isn't in this table gets an `error`.

### Energy and meals

Energy is 0 to 100. Quests cost it; Market Rush, chests, the Town Pass and talking cost nothing.

- **Free floor:** below 40, one point comes back every 4 real minutes, up to 40. Show `you.energy_regen_at`.
- **The free thali** at the Common Table: `FreeMeal`, +40, once every 24 real hours (`you.free_meal_at`). Not when full.
- **Paid meals:** `BuyMeal{"item": "thali"}`. The menu: `chai` 1 FOOD +10, `vada_pav` 3 FOOD +32, `thali` 6 FOOD +70
  (the numbers come in `city.menu`). The result comes at once with a `MealOrdered` event: the meal ticket has gone to the
  chain, and `you.meal_pending` holds its ref. **Energy fills only when the chain says it was eaten:** a `MealEaten` event
  with the `tx`, seconds later on Sepolia, at once offline. If the chain refused it (the price moved past `max_usdc`, or
  the wallet was short), a `MealFailed` comes instead, with the reason, and nothing was paid. One ticket at a time, and
  none when energy is full, so nobody can hoard.
- **A meal voucher** from a chest: `BuyMeal{"item": "thali", "voucher": true}`. The house pays the meal into your wallet
  (`VoucherUsed`), then it's bought like any other meal (`MealOrdered`, `MealEaten`). Needs the Town Pass.
- **The rescue meal:** with the Town Pass, energy under 10, less USDC than the cheapest meal and today's free thali
  already eaten, a neighbour sets off with a thali: `RescueComing` with `at`, then `RescueMeal` (the existing visitor
  scene) when it's eaten. Once a day. The safety net pays; if it's empty, the energy is given straight away
  (`direct: true`). Nobody is ever stuck.

### Market Rush

`StartRush` starts a 90-second run timed by the server: `RushStarted` has `ends_at` (real clock) and `runs_left`. Serve
with `ServeOrder`; the server ends the run at `ends_at` with `RushTimeUp` and then `RushEnded`, or the player ends it
early with `EndRush`. Three free runs a real day. A run's count goes on the season's `rush` board and today's
`city.rush.today`; each run with an order earns a ticket. At the real day's close, today's top 10 split the Rush pot:
the server pays it (`RewardPaid`), or holds it (`RewardPending`) for anyone without the Town Pass.

### Quests

| `quest` | What | Energy | Pays |
|---|---|---|---|
| `errand:<id>` | An errand from `city.errands.list`. 3 a day | 10 | `city.errands.rate` USDC, from the house |
| `campaign:<id>` | A sponsored quest from `city.bounty` | the card's `energy` | the card's `payout` USDC, from the sponsor's escrow |
| `mystery:<id>` | Today's mystery, `city.mystery.quest`. 1 a day | 50 | `city.mystery.payout`: the house's, or the boosting campaign's |
| `grandma` | Grandma's Ledger, once a season | 50 | Her strongbox: up to 1 USDC from the house, the title `Grandma's Heir` and the `grandmas-ledger` stamp |

Every finished quest also earns a ticket. Energy is spent when the quest is taken; dropping it (`AbandonQuest`) gives
back its campaign slot, not the energy. A quest in `you.quests`:

```json
{
  "quest": "campaign:1",
  "title": "The Spice Run",
  "story": "The harbourmaster has cargo money...",
  "kind": {"type": "campaign", "campaign": 1, "template": "spice_run"},
  "campaign": 1,
  "energy": 30,
  "any_order": false,
  "steps": [
    {"id": "cargo", "kind": "cargo", "text": "Collect the cargo money...", "place": "harbourmaster", "done": true, "waiting": false},
    {"id": "swap", "kind": "swap", "text": "Swap the cargo money...", "place": "kiosk", "done": false, "waiting": false,
     "quote": {"usdc_in": 500000, "amount_out": "9066109666030017277", "min_out": "8975448569369717104", "fee_bps": 3000,
               "slippage_bps": 100, "token": "0x…", "symbol": "MANGO", "decimals": 18, "quoted_at": 61000, "fresh_until": 121000},
     "quote_ready_at": 76000},
    {"id": "deliver", "kind": "deliver", "text": "Deliver the spice...", "place": "spice-merchant", "done": false, "waiting": false}
  ],
  "hold": null
}
```

Every step also has `quote` and `quote_ready_at`, `null` except on a swap step (see [the exchange kiosk](#the-exchange-kiosk)).
Steps go in order, unless `any_order` (Grandma's pages): then any order, but the strongbox is last. `place` is where to
put the quest marker: a place (`market`, `table`, `bank`, `homes`, `square`, `harbourmaster`, `kiosk`, `hall`, `stall`)
or a person. `waiting` means it's gone to the chain: show a pending stamp until `QuestStepDone` or `QuestStepFailed`.

| Step `kind` | How it gets done |
|---|---|
| `talk`, `visit` | The client sends `QuestStep{quest, step}` when the player does it |
| `paper` | `QuestStep` at the square, and only on a day with a `city.shock` (`NotAShockDay` otherwise) |
| `strongbox` | `QuestStep`, once every other step is done |
| `cargo` | `QuestStep` at the harbourmaster. If the wallet holds the cargo (0.50 USDC) it's done at once; otherwise the campaign advances what's short (`QuestStepSent`, then `QuestStepDone` when it lands), which needs the Town Pass |
| `swap` | The `Swap{quest}` command at the exchange kiosk: a real Uniswap swap of the cargo for the quest token, from the player's wallet, taking at least the step's `quote.min_out`. Needs a quote under a minute old. Done when the chain shows the swap |
| `deliver` | The `Deliver{quest}` command at the Spice Merchant (`spice-merchant.tallyport.eth`). Done when the chain shows the delivery |
| `sign` | The `PaintSign{text}` command. Done when the chain shows the record on the player's name. Needs an ENS name, so the Town Pass |
| `verify` | Done when the player gets the Town Pass, or at once for someone who has it |
| `hold` | Hold the quest token: the chain is checked at random moments over 3 days (`hold.checks_left`, `hold.passed`, `hold.ends`). Dropping below 1 token fails the quest (`QuestFailed`) |
| `meals` | Counted by the server: 3 meals paid for yourself after taking the quest |

The four sponsored templates: `spice_run` (cargo, swap, deliver; the flagship Uniswap quest), `paint_sign` (talk, sign),
`town_pass` (talk, verify), `hold_line` (talk, hold). When the last step is done, `QuestDone` says what it paid; the
USDC follows as `RewardPaid`, or waits as `RewardPending`.

### The exchange kiosk

When a Spice Run reaches its `swap` step, the server asks Uniswap what the cargo (0.50 USDC) buys, and the answer
lands on the step as `quote`, with a `SwapQuoted` event:

| `quote` field | Meaning |
|---|---|
| `usdc_in` | The cargo, in USDC base units |
| `amount_out` | What it buys of the quest token now, a **decimal string** in the token's base units: divide by 10^`decimals` to show it (18 for MANGO) |
| `min_out` | The least the swap will take: `amount_out` less `slippage_bps`. Also a decimal string |
| `fee_bps` | The pool's fee in Uniswap's units, hundredths of a basis point: `3000` is 0.30% |
| `slippage_bps` | How far under the quote the swap may fill, in basis points: `100` is 1% |
| `token`, `symbol`, `decimals` | The quest token |
| `quoted_at`, `fresh_until` | When it was quoted, and until when a swap may use it (a minute), on the real clock |

Show it in plain words: "0.50 USDC buys about 9.07 MANGO. The pool keeps 0.30%. If the price moves, you'll still get at
least 8.98 MANGO, or the swap won't happen." When the player opens the kiosk, or the quote is old, send
`QuoteSwap{quest}` for a fresh one: at most every 15 seconds (`quote_ready_at` says when; sooner is refused with
`QuoteTooSoon`). `Swap` without a quote under a minute old is refused with `QuoteStale`: ask for one, then swap. If
Uniswap couldn't quote, a `QuoteFailed` comes instead, and a new `QuoteSwap` may be sent at once.

### The Town Pass

`TownPass` answers with a one-time link, good for 15 minutes:

```json
{"type": "result", "ref": "tp-1", "ok": true, "url": "https://town.example.com/verify?token=4be1…"}
```

Open it in the browser (`OS.shell_open`). The page proves one real person with World ID, with the player's wallet as the
signal. When it's done the player gets `HumanVerified`, everything they were owed is paid, and their ENS name is
registered (`NameRegistered`). On a rehearsal server (`snapshot.debug`) the page offers a rehearsal pass instead.

### Chests and the streak

- **The daily chest** is ready once every 24 hours. Its tier is `wood`, `brass` at a 3-day streak, `gold` at 7, and one
  better the week the Town Goal is reached. It holds energy, tickets, maybe a meal voucher and maybe a **golden drop**:
  USDC from the house's SURPRISE bucket. Every 10th chest without a golden drop has one, or a meal voucher if the
  day's drops are gone.
- **The weekly chest:** come on 5 of the last 7 real days, then `OpenChest{"weekly": true}`. Once a week. It holds the
  streak bonus in USDC, tickets and energy.
- The first visit of each real day earns a ticket (`LoggedIn`, `TicketsEarned`).

### Price Call, the Town Goal and the weekly draw

- **Price Call:** before the city day closes, call tomorrow's food price `up`, `flat` or `down` (a move under 0.5% is
  flat). It's settled when the next city day starts (`PriceCallSettled`); a right call earns 2 tickets and a feed post.
- **Town Goal:** meals eaten town-wide this week, against `city.town_goal.target`. Reaching it (`TownGoalReached`, to
  everyone) makes everyone's next chest one tier better.
- **The weekly draw:** tickets are earned, never bought. When a real week closes, everyone with the Town Pass and a
  ticket is in it, one range of tickets each. The server commits a secret seed's hash on chain (`DrawCommitted`, to
  everyone, with the prize), reveals the seed 10 minutes later (`DrawRevealed`), and the chain picks the winning ticket;
  the winner gets `DrawWon` and the feed names them. Tickets without the Town Pass don't enter.

### Referrals

A new player says who sent them with `Refer{"player": "priya"}`, before their first quest is done. When they have the
Town Pass and a finished quest, both get 5 tickets (`ReferralRewarded` to the one who sent them, `TicketsEarned` to
both).

### Refusals and their numbers

Show why, using these numbers. The `type` is the name. Times are on the real clock.

| `type` | Fields |
|---|---|
| `AlreadyInRush`, `NotInRush`, `RushOver` | |
| `RushFull` | `most` |
| `NoRunsLeft`, `NoErrandsLeft`, `NoMysteryLeft` | `most`, `resets_at` |
| `UnknownItem` | `item` |
| `UnknownPlayer` | `account` |
| `RefUsed`, `MealPending` | `ref` |
| `NotEnoughEnergy` | `have`, `need` |
| `EnergyFull` | `energy` |
| `FreeMealNotReady`, `ChestNotReady` | `ready_at` |
| `WeeklyChestNotReady` | `days`, `need` |
| `NoWallet`, `NoVoucher`, `NeedsTownPass`, `BudgetSpent`, `NoName`, `NotAShockDay` | |
| `QuoteTooSoon` | `ready_at` |
| `QuoteStale` | `quest`: send `QuoteSwap`, then `Swap` again |
| `NotEnoughUsdc` | `have`, `need` (USDC) |
| `UnknownQuest`, `AlreadyOnQuest`, `NotOnQuest`, `QuestDoneBefore` | `quest` |
| `WrongStep` | `quest`, `step`: the step to do next |
| `StepWaiting` | `quest`, `step`: the step waiting for the chain |
| `CampaignClosed`, `NoSlotsLeft` | `campaign` |
| `PerHumanCap` | `campaign`, `cap` |
| `BadSign` | `most` |
| `AlreadyCalled` | `day` |
| `AlreadyHuman`, `ReferringYourself`, `AlreadyReferred`, `TooLateToRefer` | |
| `TryAgain` | | `TownPass` couldn't make a link just now (the server's randomness failed). Ask again |
| `NotEarned`, `AlreadyCarved` | `first` |
| `QuestionTooLong` | `max` |
| `UnknownPost`, `AlreadyReacted` | `post` |
| `UnknownEmote` | `emote` |
| `FollowingYourself` | |
| `NotFollowing` | `player` |

A message the server can't read gets `{"type": "error", "message": "..."}`, and the connection stays open. An error
changes nothing, and it's always a client bug.

## What the server sends on its own

| Message | When | Use it for |
|---|---|---|
| `event` | Something happened | Staging it |
| `you` | After your numbers change, and when energy comes back by itself | Replace what you hold |
| `city` | After city numbers change | Replace what you hold |
| `time` | Every few seconds | Correcting the clocks |

```json
{"type": "event", "seq": 42, "event": {"type": "OrderServed", "account": "sam", "served": 3, "ref": "sam:sam-0042"}}
{"type": "you", "you": {"name": "sam", "...": "the same fields as in a snapshot"}}
{"type": "city", "city": {"day": 3, "...": "the same fields as in a snapshot"}}
{"type": "time", "day": 3, "day_ms": 3600000, "day_elapsed_ms": 125000, "now_ms": 10925000}
```

`seq` is the log's line number and only goes up. Several events can share one `seq` when one thing caused them all.
An event's `ref` carries the player's name as a prefix. Events come before the `you` and `city` they led to, and both
come before the command's `result`. What the chain does arrives later, as its own events, on its own `seq`.

### Events for one player

Sent only to the person named in them (`ReferralRewarded` goes to both).

| Event | Fields | In the world |
|---|---|---|
| `Arrived` | `account`, `energy` | The harbourmaster hands over the letter |
| **v3** `LoggedIn` | `account`, `day`, `streak`, `week_days` | The streak counter at the door |
| `RushStarted` | `account`, **v3** `ends_at`, `runs_left` | Behind the stall, the 90-second timer starts |
| `OrderServed` | `account`, `served`, `ref` | The order is handed over, the combo climbs |
| **v3** `RushTimeUp` | `account`, `served` | The bell: time's up. A `RushEnded` follows |
| `RushEnded` | `account`, `served` | The run's score |
| **v3** `FreeMealEaten` | `account`, `energy`, `next_at` | The free thali at the Common Table |
| **v3** `MealOrdered` | `account`, `item`, `food`, `max_usdc`, `ref` | The meal is paid for: a pending stamp |
| `MealEaten` | `account`, `item`, `usdc`, `food`, `energy`, **v3** `from_ration`, `ref`, `tx` | Energy fills. `usdc` is what the chain charged, `tx` the transaction (show a link). `from_ration` is FOOD from the ration shop, at the ceiling price |
| **v3** `MealFailed` | `account`, `item`, `ref`, `reason` | The meal didn't go through; nothing was paid |
| **v3** `VoucherUsed` | `account`, `item`, `ref` | A voucher is being spent |
| **v3** `WalletReady` | `account`, `address` | The wallet panel fills in |
| **v3** `BalanceChanged` | `account`, `usdc` | The wallet's USDC |
| **v3** `HumanVerified` | `account` | The Town Pass is stamped |
| **v3** `NameRegistered` | `account`, `name` | The name plate: `sam.tallyport.eth` |
| **v3** `SignPainting` | `account`, `text` | The sign painter at work: pending |
| **v3** `RecordsSet` | `account`, `records` | The name's records changed on chain (the sign, title, stamps) |
| **v3** `QuestTaken` | `account`, `quest`, `energy` | The quest log gains a page |
| **v3** `QuestStepSent` | `account`, `quest`, `step`, `ref` | A step went to the chain: pending stamp |
| **v3** `QuestStepDone` | `account`, `quest`, `step` | Tick it off |
| **v3** `QuestSwapped` | `account`, `quest`, `received` (decimal string, the quest token's base units) | The Uniswap swap landed: show what actually arrived next to the quote. Comes just before the swap step's `QuestStepDone` |
| **v3** `QuestStepFailed` | `account`, `quest`, `step`, `reason` | The chain refused it; it can be tried again |
| **v3** `SwapQuoted` | `account`, `quest`, `usdc_in`, `amount_out`, `min_out`, `fee_bps`, `slippage_bps`, `symbol`, `decimals` | The kiosk's board shows the quote. `amount_out` and `min_out` are decimal strings |
| **v3** `QuoteFailed` | `account`, `quest`, `reason` | The kiosk couldn't get a quote; ask again |
| **v3** `QuestDone` | `account`, `quest`, `title`, `reward: {usdc, tickets, title, stamp}` | The quest's finale. `usdc` follows as `RewardPaid`, or waits |
| **v3** `QuestAbandoned` | `account`, `quest` | |
| **v3** `QuestFailed` | `account`, `quest`, `reason` | Hold the Line dropped below the line |
| **v3** `ChestOpened` | `account`, `weekly`, `tier`, `contents: {energy, tickets, voucher, golden_drop}` | The chest animation. `golden_drop` is USDC, 0 for none |
| **v3** `TicketsEarned` | `account`, `tickets`, `why`, `total` | `why`: `streak`, `rush`, `chest`, `weekly chest`, `quest`, `price call`, `referral` |
| **v3** `RewardPending` | `account`, `amount`, `why`, `ref`, `waiting` | Owed, not yet paid: `town_pass` (get the pass to be paid), `budget` (the house's budget for today is spent, so tomorrow) or `chain` (the chain refused it; tried again tomorrow) |
| **v3** `RewardPaid` | `account`, `amount`, `why`, `ref`, `tx` | USDC landed in the wallet |
| **v3** `PriceCalled`, `PriceCallSettled` | `account`, `day`, `call`, and `moved`, `right` | |
| **v3** `RescueComing` | `account`, `at` | A neighbour sets off |
| **v3** `RescueMeal` | `account`, `energy`, `direct` | The neighbour arrives with a thali |
| **v3** `Referred` | `account`, `by` | |
| **v3** `ReferralRewarded` | `account`, `friend`, `tickets` | |
| **v3** `DrawWon` | `account`, `week`, `prize`, `tx` | You won the week's draw |
| `FirstEarned` | `account`, `first` | The milestone blast |
| `FirstCarved` | `account`, `first` | The Wall |
| `MentorAsked` | `account`, `question` | |
| `MentorSays` | `account`, `about`, `text` | The mentor's line |
| `Followed`, `Unfollowed` | `account`, `player` | |

Firsts: `first_meal`, `first_quest`, `town_pass`.

### Events for the whole city

Sent to everyone connected.

| Event | Fields | In the world |
|---|---|---|
| `DayOpened` | `day`, `open_price` | New price tags |
| `FoodIndexSet` | `day`, `day_price`, `food_index_bps` | The day's average. `day_price` is 0 after a quiet day |
| `TradeCounted` | `day`, `usdc`, `food`, `price_after` | The price board ticks |
| `FoodBought` | `day`, `wanted`, `bought`, `usdc_paid`, `ref` | Offline, a meal's FOOD bought from the town's pool. `bought < wanted`: today's limit hit, the ration shop covered it |
| `FoodSold` | `day`, `offered`, `sold`, `usdc_got`, `ref` | Kofi sells the harvest |
| `CityEventStarted` | `day`, `kind`, `days` | A festival, a harvest or a drought arrives |
| `PaperPublished` | `day`, `headline`, `stories` | The morning paper |
| `SeasonChanged` | `season`, `shock` | A new season |
| `FeedPost` | `id`, `day`, `kind`, `text`, `about` | The feed |
| `Reacted` | `post`, `account`, `emote` | Add 1 to that post's count |
| **v3** `TownGoalReached` | `week`, `meals`, `target` | The town celebrates |
| **v3** `DrawCommitted` | `week`, `tickets`, `prize` | The draw is sealed |
| **v3** `DrawRevealed` | `week` | The draw is drawn |
| **v3** `BountyPosted` | `campaign`, `template` | A new card on the Bounty Board |
| **v3** `BountyClosed` | `campaign` | A card comes down |
| **v3** `LedgerUpdated` | `part`: `house`, `treasury` or `float` | The pools' numbers in `city` changed |

## The Tally

*The Dhaniverse Tally* is written once a city day, each morning from day 1, from the real events since the last paper. If it
didn't happen, it isn't in the paper. It reports food prices, the menu's changes, festivals, harvests and droughts, and
firsts. **What anyone paid, earned or owes never appears.** `headline` is one short line, and `stories` holds up to 5
short paragraphs and can be empty. `city.paper` holds the latest, for anyone connecting mid-morning.

## Names, secrets and other people

### Saying hello

The client makes the secret itself, once: 32 random hex characters from `Crypto.generate_random_bytes(16).hex_encode()`
will do. It saves the secret on the player's machine and never shows it. The server keeps only a hash.

**A new player has no name yet.** They write it on the ferry ticket during the opening, so the client connects first by
leaving `player` out:

```json
{"type": "hello", "protocol": 3, "secret": "9f3c1e7a0b5d4c2e8a6f1d3b7c9e0a42"}
{"type": "nameless"}
```

A nameless connection gets no `you`, `city` or `presence`, and anything other than `ClaimName` gets an `error`. When the
player finishes the ticket, send `ClaimName` as a normal command:

```json
{"type": "command", "ref": "ticket-1", "command": {"type": "ClaimName", "name": "sam"}}
{"type": "snapshot", "seq": 41, "debug": false, "you": {...}, "city": {...}}
{"type": "result", "ref": "ticket-1", "ok": true}
{"type": "result", "ref": "ticket-1", "ok": false, "refusal": {"type": "NameTaken", "name": "sam"}}
```

On `ok: false` nothing has changed, so let them write another. If the connection drops mid-claim, say the nameless
`hello` again and send `ClaimName` again. **Save the name once you see the snapshot,** and use the two-field `hello`
from then on. A `hello` with both `player` and `secret` also claims a free name in one step, for bots and the stage; its
refusal comes as `{"type": "hello_refused", "refusal": {...}}`.

| Refusal | Fields | When |
|---|---|---|
| `BadName` | `name` | Not 3 to 20 characters of `a-z`, `0-9` and `-`, a dash at either end, `--`, or rude |
| `NameTaken` | `name` | Someone else holds it, or it's a resident's. Also a returning player whose saved secret is wrong |
| `BadSecret` | | The secret is missing, or isn't 16 to 128 characters. A client bug |
| `SlowDown` | | Too many tries from this address |

A name is valid as an ENS label: it becomes `name.tallyport.eth` with the Town Pass. Lowercase the player's typing
before you send it.

**Limits, per address:** 120 new connections a minute and 32 open at once. 60 name tries a minute and 10 new names an
hour, past which you get `SlowDown`.

### Moving and seeing each other

Send your position a few times a second while it's changing. It isn't saved, and no reply comes back.

```json
{"type": "move", "x": 12.5, "y": 0.0, "z": -3.25, "yaw": 1.57, "anim": "walk"}
```

`anim` is the client's own clip name, up to 24 characters. Everyone connected gets the whole list 5 times a second,
whenever anything in it has changed:

```json
{"type": "presence", "players": [{"name": "sam", "x": 12.5, "y": 0.0, "z": -3.25, "yaw": 1.57, "anim": "walk", "title": "Regular"}]}
{"type": "left", "name": "sam"}
```

- The list includes you, so skip your own name. Replace what you hold each time.
- `title` is the player's title, as in `you.title`. It says nothing about money.
- `left` goes to everyone else when someone on the list disconnects. A takeover isn't a leaving.

### Residents

About 20 people live in town. They walk between the town's places so it isn't empty, and they appear in `presence`:

```json
{"name": "Asha", "resident": true, "from": "market", "place": "bank", "anim": "walk", "title": "Resident"}
```

- A resident has no position. `place` is one of `market`, `table`, `bank`, `homes` or `square`: walk them there from
  `from`, and choose where within it they stand. `anim` is `walk` for `city.resident_walk_ms`, then `idle`.
- They don't eat, quest or hold money, and they never show on a board, in the feed or on a profile.

## The feed, the boards and profiles

**None of these ever show an amount anyone paid, earned, owes or holds.** That's enforced on the server.

### The feed

`snapshot.feed` is the latest 30 posts, oldest first. New ones come as `FeedPost`. `text` is plain English, ready to
show. `about` is the player it's about, or `null` for the town. `kind` is for an icon: `first`, `board`, `city`,
`season`, **v3** `quest` (a sponsored quest, mystery or Grandma's Ledger finished), `call` (a right Price Call), `goal`,
`draw` (who won, never what) or `bounty`. `city.emotes` lists the emotes. One reaction per player per post, and only the
latest 200 posts can be reacted to. `you.following` lists who you follow. A meal, a rescue, a payout or a chest is never
posted.

### The boards

```json
{"boards": {"rush": [{"rank": 1, "name": "sam", "title": "Regular"}]}}
{"ranks": {"rush": 4}, "best_board": "rush", "neighbours": {"rush": [{"rank": 3, "name": "priya", "title": "Newcomer"}]}}
```

`rush` ranks each player's best Market Rush run this season. Each board is the top 10, with rank, name and title only.
`ranks` is your own place, or `null` before your first run. `neighbours` is you and two either side. A new season clears
the boards; names and firsts stay. Today's Rush pot ranks today's best runs, in `city.rush.today`.

### Profiles

```json
{"type": "profile", "name": "sam"}
{"type": "profile", "found": true, "name": "sam", "title": "Spice Runner", "firsts": ["first_meal"], "stamps": ["spice-run"], "ens": "sam.tallyport.eth", "sign": "Sam's chai", "town_pass": true, "days_active": 4, "reputation": "Known around town"}
{"type": "profile", "found": false, "name": "nobody"}
```

`reputation` comes from days in town: `New in town`, `Known around town` (3), `Reliable` (30) or `Pillar of the town`
(120). Residents have no profile. Everything here is public anyway, on the player's ENS name.

## The mentor

After something real happens to a player, the mentor names it in plain words, once. It only reads that player's own
events, and it never changes anything. A word is never used before the player has met the thing behind it.

| `about` | Said after |
|---|---|
| `inflation` | The first time the same meal costs them more than last time |
| `reply` | An answer to `AskMentor` that isn't one of the above |

If a question touches something the player has met, it gets that plain explanation again. If it touches something they
haven't, the answer says so without naming it. Asking more than 30 times a minute from one address gets an `error`.

## Seasons

A season is 168 city days, one real week. Each brings one shock, in turn: a harvest, a festival, then a drought. The shock
starts as a real city event. `city.season` says which season it is and the day it ends. Grandma's Ledger can be done
once a season.

## Fair play

| Refusal or limit | When |
|---|---|
| `RushFull` (`most`) | `ServeOrder` past the run's customers |
| `error` "too many commands" | More than 300 commands a minute from one player |
| `error` "that ref is too long" | A `ref` over 64 characters |
| `MealPending`, `EnergyFull` | A second meal ticket, or a meal when full: nobody can hoard energy |
| `PerHumanCap`, `NoSlotsLeft` | A sponsored quest past its per-person cap, or with every slot taken |

Payouts need the Town Pass, one World ID holds one player, every payout ref works once on chain, and the house never
promises more than its budget for the day.

## HTTP

Plain HTTP on the same port as the WebSocket.

```
GET  /city                  the town, as JSON (public view)
GET  /health                whether the server is alive
GET  /verify?token=…        the Town Pass page (web/verify.html)
GET  /verify/session?token= the page's session: who, which wallet, and World ID's settings
POST /verify                the page's proof, {"token", "result"}
GET  /console, /dashboard   the sponsor console and the treasury dashboard (web/); / is the dashboard
GET  /<path>                any other file in web/, except web/dev and web/tools
GET  /deployments.json      the contracts' addresses for the pages, with "rpcUrl" if one is set
GET  /arkiv/campaigns       the Bounty Board's cards from Arkiv, through the publisher, cached 10 seconds
POST /swarm/campaign-bundle a campaign's story and image for Swarm, passed through to the publisher
```

### The public view

`/city` is rebuilt every 5 seconds, sent with `Access-Control-Allow-Origin: *` and `Cache-Control: public, max-age=5`.

```json
{
  "protocol": 3,
  "chain": "sepolia",
  "world_app_id": "app_…",
  "day": 12,
  "day_ms": 3600000,
  "season": {"number": 1, "shock": "", "ends_day": 168},
  "price": 4121,
  "food": {"price": 4121, "floor": 2000, "ceiling": 8000, "meals_today": 12, "usdc_today": 96000, "open_price": 4000, "food_index_bps": 10200, "shock": "", "menu": [{"name": "chai", "price": 4121, "was": 4080}]},
  "paper": {"day": 12, "headline": "A quiet day in Dhaniverse", "stories": []},
  "boards": {"rush": [{"rank": 1, "name": "sam", "title": "Regular"}]},
  "bounty": [{"id": 1, "kind": "sponsored", "sponsor": "0x…", "title": "The Spice Run", "template": "spice_run", "payout": 1000000, "energy": 30, "slots": 50, "slots_left": 47, "claims": 3, "humans": 3, "budget": 45000000, "spendable": 45000000, "paid": 3000000, "remaining": 42000000, "daily_cap": 6000000, "starts": 1793921395, "ends": 1794526195, "status": "live", "swarm": null}],
  "house": {"...": "as in city.house"},
  "treasury": {"...": "as in city.treasury"},
  "float": {"...": "as in city.float"},
  "town_goal": {"week": 1, "target": 200, "progress": 40, "reached": false},
  "draw": {"week": 1, "tickets": 31, "prize": 5000000},
  "feed": [{"id": 12, "day": 3, "kind": "first", "text": "sam bought a first meal.", "about": "sam", "reactions": {"clap": 2}}],
  "people": [{"name": "sam", "title": "Spice Runner", "stamps": ["spice-run"], "ens": "sam.tallyport.eth"}],
  "online": 3,
  "residents": 20
}
```

**Nothing private is here:** no energy, wallet, balance, run, meal, quest, ticket count, pending payout, score or secret
of anyone's. The money numbers are the town's totals: pools, revenue, campaigns. **Limits:** 120 requests a minute per
address, past which a `429`. `/health` answers `{"ok": true, "seq": 41, "day": 12, "chain": "offline", "block": 7}`, or a
`503` if the city has stopped for 30 seconds.

### The Town Pass over HTTP

`GET /verify/session?token=T` answers the verify page:

```json
{"player": "sam", "wallet": "0x…", "expires_at": 1794000000, "verified": false, "human_id": null, "ens": null,
 "app_id": "app_…", "action": "tallyport-town-pass", "environment": "production", "allow_legacy_proofs": true,
 "rp_context": {"rp_id": "…", "nonce": "0x…", "created_at": 1793999700, "expires_at": 1794000000, "signature": "0x…"},
 "rehearsal": false}
```

A fresh signed `rp_context` comes with every call. An unknown token gets `404 {"error": "token_unknown"}`; an expired or
used one `410 {"error": "token_expired"}` or `410 {"error": "token_used"}`.

`POST /verify` with `{"token": "…", "result": <IDKit's result>}` answers `200 {"ok": true, "human_id": "0x…", "ens":
"sam.tallyport.eth"}`, or `{"ok": false, "error": …, "message": …}` with a 4xx: `invalid_proof` (400),
`already_verified` (409, also when that World ID holds another player), `token_expired` or `token_used` (410). On a
rehearsal server, `result` `{"offline": true}` is a rehearsal pass, and the answer says `"rehearsal": true`.

### Arkiv and Swarm

`GET /arkiv/campaigns` passes on the publisher's `{"cards": [...], "source", "block", "stale", …}`. If the publisher
isn't answering it says so: `503 {"error": "unavailable", "message": "…"}`; show `city.bounty` instead.
`POST /swarm/campaign-bundle` passes a multipart body to the publisher unchanged, and its answer back.

## Rehearsal commands

Only when the server was started with `--debug`, which `snapshot.debug` reports. Otherwise each gets an `error`.

```json
{"type": "debug", "action": {"type": "Skip", "ms": 3600000}}
{"type": "debug", "action": {"type": "NextSeason"}}
{"type": "debug", "action": {"type": "ReadyChest"}}
{"type": "debug", "action": {"type": "Fund", "usdc": 1000000}}
{"type": "debug", "action": {"type": "FundBucket", "bucket": "safety", "usdc": 5000000}}
{"type": "debug", "action": {"type": "PassTown"}}
{"type": "debug", "action": {"type": "NewCampaign", "template": "spice_run", "payout": 1000000, "energy": 30, "slots": 10, "boosted": false}}
```

- `Skip` moves the whole city forward, exactly as if the time had passed: runs end, rescues arrive, days and weeks close.
- `NextSeason` starts the next season at once. `ReadyChest` makes your daily chest ready now.
- Offline only: `Fund` puts USDC in your wallet, as a faucet would. `FundBucket` puts USDC in a HousePool bucket
  (`fixed`, `surprise` or `safety`). `PassTown` gives you a rehearsal Town Pass. `NewCampaign` opens a campaign as a
  sponsor would, refused like CampaignEscrow refuses one that breaks the 25% rule or pays under 0.15 USDC.

Each one is answered with a fresh `you`, then `{"type": "debug_done"}`, after its events; a rehearsal that couldn't be
done also gets an `error` saying why.
