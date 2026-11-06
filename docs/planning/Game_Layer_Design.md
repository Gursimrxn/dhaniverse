> **Engine note.** The browser now runs the Godot web export, not a Rust core. Where this says "game-core", read: the rules run on the Rust server, and the Godot client only shows them and sends inputs (no shared Rust code in the browser).

# Dhaniverse: the game layer and its UX

Draft for the founder to react to. Nothing here is built.

This is what players actually do in the browser client from `Web_Client_Design.md`: the opening and the first hour,
the quests as real games, the chests and the other things that bring people back, and every piece of HUD and UI.
The economy is the technical plan's, unchanged: USDC is the only money, energy comes from food, sponsors and the
house pool pay, and nobody gets stuck. Where an idea needs the server to change, it is listed under *What the server
needs*. Decisions that are yours are at the end, under *Questions for the founder*. Nobody new is added or named: the
people here are the roles the town already has (the harbourmaster, the clerk, the old trader) and its residents.

## In one screen

- **The opening keeps your order:** black, the logo, the ferry docking under the Tallyport card, the name and the
  menu, the name on the ferry ticket, the harbourmaster, Gran's letter. Then the first hour runs with no tutorial
  panels. The ticket you write your name on becomes your Town Pass, and then your passport of stamps.
- **Every quest becomes a game you can get better at.** Market Rush's serve-orders loop is replaced by a 90-second
  trading sprint in which your own trades move the prices. Errands become four short skill games. The Spice Run gets
  a real lever, a real scale and a carry across town. The daily mystery becomes a detective case you have to crack.
- **Skill earns medals, not money.** A quest that costs energy pays a fixed amount, printed on its card. Skill decides
  the medal, and medals pay tickets and titles. Only free contests rank people for USDC.
- **Chests are a moment, and an honest one.** The chest at your door shows its odds on a brass plate and its pity
  count as rivets round the lock. Random USDC only ever comes out of free things, paid by the surprise bucket.
- **New mechanics:** hold-to-trade with a needle you can feel move, ghosts of your best run and of today's leader,
  receipts for every cent, the passport, tear-off quest cards, the Scale at the exchange, neighbours who carry a
  rescue meal, lanterns for the Town Goal, sponsor weeks for chests.
- **The HUD keeps the dark plates you liked,** only where words sit on the moving world: energy, money, the clock,
  the map and dialogue. Everything else lives on real things in town, each with a physical action.

## Ten rules every game here follows

The plan's money rules, turned into rules for designing play.

| # | Rule | Why |
|---|---|---|
| 1 | A quest that costs energy pays a fixed amount, printed on its card before you take it. | Energy is bought with USDC. If skill set the payout, the quest would read as a stake (the plan's Risks section, on Indian law). |
| 2 | Skill decides the medal: gold, silver or bronze. Medals pay tickets and titles, never USDC. | Keeps every amount fixed and every reward for skill non-money. |
| 3 | You can always finish what you started. Failing a section costs time and the medal, never the quest or more energy. Hold the Line is the exception: failing it is its lesson. | The energy buys a job, not a gamble. |
| 4 | A contest that ranks players for USDC costs nothing to enter. Today that is Market Rush. | The plan: contests cost no energy. |
| 5 | Random USDC comes only from free things (the daily chest and the weekly draw), paid from the surprise bucket. Nothing random is sold, and no quest reward is random. | The plan's two buckets, and chests are never sold. |
| 6 | The server decides every amount and every score. The browser predicts, then shows what the server decided. | `Web_Client_Design.md`, real money section. |
| 7 | Every game of timing, aim or routing has a free practice: the same game, with no energy, no pay and no medal. | Nobody spends energy learning. |
| 8 | Odds and pity are printed on the thing that has them. | Trust, and the anticipation is half the fun. |
| 9 | Games keep score in fruit, crates, seconds and medals. No game invents money. | The plan: no coins, no play money. |
| 10 | Every moment comes from a real event or from the player's own action. Nothing plays on a timer for show. | Your rule against staged and hardcoded moments. |

---

## Part 1. The opening and the first hour

### The opening, in your order

| # | Beat | What you see and do | Length |
|---|---|---|---|
| 1 | Black | The page opens on black while the first playable streams in (at most 1 MB, at most 2 s on 20 Mbps). A thin cream line fills under the centre. It moves only as files arrive, from the manifest's real sizes, so it never fakes progress. | 0–2 s |
| 2 | The logo | The real mark (`brand-mark.svg`) appears through a mask, left loop then right (0.9 s). The real wordmark (`brand-wordmark.svg`) slides out from behind it (0.5 s). One sweep through the five colourways crosses the mark (0.8 s), then it rests in cream. No sound yet: browsers block sound until a key or a click. "Press any key" fades in under it, small, in Bitroad at 60% cream, with no pulse. | 2.4 s |
| 3 | The key | Any key or click unlocks sound. Two soft notes play, and the screen closes onto the mark and opens out through it onto the river at dawn (the mark wipe, 1 s). | 1 s |
| 4 | The ferry docks | From across the water, with the sun coming up behind the town, the ferry comes slowly up the river to the jetty. The camera closes in only a little and never zooms onto the flag. The Tallyport card (the word in Instrument Serif, cream, lower third) fades in at 2 s and out at 5.5 s. Letterbox bars. Sound: water on the hull, the engine, the town waking, the horn as it comes alongside. The town is live: residents walk the landing and the market board shows today's real price. Esc skips after 1.5 s, when a keycap appears bottom right. | about 14 s |
| 5 | The name and the menu | Only once the ferry is alongside: the wordmark across the sky, and the menu bottom left in plain words: **Continue** (as sam), **A new life** (step off the ferry), **Settings**. Beside it, one line of the live town: food price now with its arrow, people in town, and today's headline from The Tally. The headline changes with a fade, never a scrolling ticker. The camera drifts very slowly. W and S or the arrows move, Enter chooses. | until you choose |
| 6 | On deck | **A new life:** the camera comes down from the title shot to the foredeck (1.8 s) and the deck is yours. If you stand still for 6 s, a key hint appears over you: "W Walk". | 1.8 s |
| 7 | The ticket | At the gangway gate, a small sign says Tickets. Press E and your character takes out the ferry ticket and holds it up in the shot: TALLYPORT FERRY · ONE WAY, PASSENGER blank. What you type inks onto the line in Instrument Serif italic, lowercased as you go (3 to 20 letters, numbers or dashes). Enter claims the name. If it's taken or not allowed, the ink smudges and a note writes itself in orange: "Someone in town already goes by that." Accepted: hold E to clip the ticket in the gate's brass clipper (a click, a clean hole, the paper dot falls) and the gate swings open. Behind it the server makes your wallet; you never see a seed phrase or gas. | your pace |
| 8 | The harbourmaster | Down the gangway he waves: "Over here, sam!" (on the dialogue plate, every 9 s until you come). Within 3 m the bars come in, an over-the-shoulder shot with the landing behind him: "Morning, sam. I've something for you. From your gran." He hands over an envelope. | about 4 s |
| 9 | Gran's letter | The envelope opens in your hands: the letter, held up as paper, and a key that drops into your palm. E folds it away. He says one line, the morning comes up over 10 s, and the HUD plates fade in (1.4 s). | your pace |

Everything after the logo is a cutscene in the brand's look: ink letterbox bars, cream title cards, subtitles on the
lower bar, and the mark wipe between places. The ferry film and the harbourmaster's shot are animated in Blender and
played by the cutscene player, with the live town around them.

Words that change (proposals; the letter's body stays as it is):

- Gran's postscript, which now points at the key instead of Kofi's stall: *"P.S. The key is for my door at the Homes.
  Whatever the town leaves on the step is yours now."*
- The harbourmaster, after the letter: *"She was a good one, sam. If you want work, the ferry's cargo won't unload
  itself."*

What changes from today's opening:

- **The ticket is a thing in the shot,** held in your hands, not a sheet over the screen. Typing goes into a hidden
  text field, so accents and screen readers work, and what you type is drawn onto the ticket itself.
- **The ticket stays with you.** The Town Pass is stamped onto it, and it becomes your passport (Part 3).
- **The letter carries a key.** It opens Gran's door at the Homes, where the daily chest waits. Your first chest is
  minutes away instead of a day.
- **The menu loses Leave,** because a browser tab can't close itself (see Questions), and the title's news ticker
  stops scrolling.
- **Your first job is The Unload,** a real skill game, instead of Kofi's stall.

### The first hour

No checklist panel. Each step has a person or a thing in town pointing at the next, and the minimap's gold marker.
Any order works.

| Step | Where | What happens | Server |
|---|---|---|---|
| The first job | The harbour crane | The harbourmaster offers The Unload (an errand: 10 energy of the 100 you arrive with; always The Unload for a newcomer, whatever the day's list). You learn the run screen, the medal and pay. The pay slip prints: "Held for you: get your Town Pass." | `TakeQuest`, a run, `QuestDone`, `RewardPending` (`town_pass`) |
| The Town Pass | The town hall desk | Behind the clerk, an envelope with your name on it holds everything you're owed, and it fattens as more waits. World ID in the page. Hold E to bring the clerk's stamp down on your ticket, and the full milestone blast plays. Your name is lettered on as `sam.tallyport.eth`, and the envelope is handed over. | `TownPass`, `HumanVerified`, `NameRegistered`, `RewardPaid` |
| The free thali | The Common Table | Take a plate from the community pot: +40 energy. The menu board beside it shows the live prices. | `FreeMeal` |
| The Bounty Board | Tally Square | Cards say who pays, the energy and the USDC. Hold E to tear one off. | `TakeQuest` |
| Your door | The Homes | Gran's key opens her door. The daily chest is there, ready. | `OpenChest` |

The mentor names a thing only after you've met it: "That was price impact", never before. Boards and rankings appear
after your first run, not in the first minutes (the research in `docs/design/research_game_feel_and_retention.md`,
4.9).

### Coming back

- **Continue** goes through the mark straight to where you left off. No ferry.
- **On a new device**, Continue becomes Sign in, through the wallet's passkey.
- **A crash before the letter** resumes at the harbourmaster, as it does today.
- **A saved name the server refuses** gets a fresh ticket on the landing, then carries on.

---

## Part 2. Quests as real games

### How every skill game works

Written once here; each page below only says what is different.

- **Start.** At the game's spot, a card shows the medal times and the controls. E starts: `StartRun`. The server sends
  the run's id, the hash of its seed and when it ends. A 3, 2, 1 in Bitroad (0.6 s each, a tick each), while the
  camera settles into the game's own framing.
- **During.** The browser runs game-core at 60 Hz and predicts, so it feels instant. It sends its inputs every 100 ms.
  The server runs the same game-core in real time on its own clock, and its state is the truth. The world's chance
  events (a boat docks, a gust) reach the browser from the server a second or two before they happen, and the game
  shows that lead as its warning. The browser never knows the future.
- **End.** At the bell, or when the job is done: the server's score and medal, and the seed, which anyone can check
  against the hash. The result prints on a job slip, held up for 3 s, then pocketed.
- **Medals.** Fixed thresholds per game, from `rules.toml`, shown before you start and as marks on the run's clock.
  Gold +2 tickets, silver +1 (proposal). Your best medal per game shows in your passport.
- **Practice.** The same game run in the browser alone, with no energy, no pay, no medal and no board.
- **Ghosts.** The server keeps every run's inputs (it needs them to check runs). Your best run and today's leader can
  ride along as translucent ghosts, replayed by game-core from inputs and seed. A ghost shows a name and a title only.
- **Cheating gets nothing.** Speed hacks fail against the server's clock. Edited scores mean nothing. A replayed run
  fails because inputs are bound to a server session and seed. Movement inside a run is simulated on the server, so
  you can't act at a spot you aren't standing at. Each game lists its own bot tells. Suspicious runs are held for
  review instead of paid, and the per-human caps bound the rest.
- **Disconnect.** The run ends where it stands, and still counts (as Market Rush does today).

### The games at a glance

| Game | Where | Kind | Skill | Energy | Pays (fixed) | Funded by | Teaches |
|---|---|---|---|---|---|---|---|
| Market Rush | Market Hall | daily contest | routing, timing, nerve | 0 | top 10 split today's pot | house, fixed bucket (30% share) | price impact, arbitrage |
| The Spice Run | landing to Market Hall | sponsored (Uniswap) | a steady carry | 30 | the card: 1.00 at launch, which is 0.50 cargo back and 0.50 reward | sponsor escrow | swaps, fees, slippage, a small loan |
| Paint Your Shop Sign | Market Hall door | sponsored (ENS) | a steady hand | 20 | the card: 0.25 at launch | sponsor escrow | owning your name |
| Hold the Line | Market Hall | sponsored | patience | 20 | the card | sponsor escrow | volatility |
| The Town Pass | town hall | onboarding | none, on purpose | 0 | the card (0.20 at launch) and everything you're owed | sponsor escrow | one person, one pass |
| The Unload | harbour crane | errand | timing, risk | 10 | today's errand rate | house, fixed bucket (15% share) | locking in gains |
| The Post Run | harbour to the Homes | errand | aim, reading | 10 | today's errand rate | house, fixed bucket | spotting scams |
| The Weigh House | Market Hall | errand | precision | 10 | today's errand rate | house, fixed bucket | margins |
| Lamplighter | waterfront | errand | planning | 10 | today's errand rate | house, fixed bucket | budgeting |
| The Daily Mystery | all over town | mystery, 1 a day | deduction, stealth | 50 | today's mystery: 0.50, or a sponsor's boosted pot up to 5.00 | house, surprise bucket (15% share), or a sponsor | money crimes |
| Grandma's Ledger | town and your door | once a season | puzzles | 50 | strongbox 1.00, 5 tickets, Grandma's Heir | house, surprise bucket | one lesson a page |

"At launch" means the campaigns in `rules.toml`. Errand pay is `city.errands.rate` (0.04 USDC in the protocol's
example). Every finished quest also earns 1 ticket. Every one of these passes the plan's 25% rule as it does today:
the games change how a quest is played, not what it costs or pays.

### Market Rush: the trading sprint

Replaces Kofi's stall and its serve-orders loop. Four stalls, two fruits, one bell.

- **Numbers.** 0 energy. 3 runs a real day, plus free practice in the empty hall after hours. 90 s. Ranked by today's
  best run. At the real day's close, today's top 10 split the pot (weights 25, 18, 14, 11, 9, 7, 6, 4, 3, 3), paid to
  Town Pass holders and held for the rest. 1 ticket for each run with at least one trade.
- **The game.** You walk into the Market Hall at rush hour with a basket of 20 apples. Four stalls trade apples for
  mangoes, each at its own price, shown on a big brass dial: how many apples one mango costs there right now. A cream
  line on every dial marks the hall's average. Needle left of it: mangoes are cheap here. Right of it: dear.
  - Hold the left mouse button (or E) at a stall to buy mangoes, one every 0.25 s. Hold the right button (or Q) to
    sell them. Every mango moves that stall's needle, because each stall is its own little pool: the more you trade,
    the worse your price. The stall rounds every trade in its own favour, and that is its fee.
  - A stall you leave drifts back toward the average over about 6 s.
  - Three to five rival traders work the same gaps. Where they trade, the needle moves.
  - Events, each warned 2 s ahead by one bell and the stall's lamp: **Boat in** (mangoes flood one stall, cheap for
    8 s), **Mango rush** (a crowd, dear for 8 s), **Shutters** (a stall closes for 5 s). Everyone gets the same set of
    events that day, each run in its own order and timing.
  - At 10 s left the hall drops to evening light and the shutters start coming down. At the bell only apples count.
- **Skill.** Reading four dials at a glance, routing between them, holding just long enough, reacting to a warning,
  and getting back into apples before the close.
- **Thrill.** The needle sliding under your hold, with a ratchet click that falls in pitch as your price worsens. A
  rival walking toward your gap. The last ten seconds. Today's leader as a ghost beside you.
- **Feedback.** Each fruit arcs between basket and crate (instanced particles). A round trip that ends with more apples
  than it started: a small brass ding, and your count turns green for 0.3 s. No shake. The camera sits high behind
  you (about 6 m), with the whole hall readable.
- **Failure.** Mangoes left at the bell count for nothing. Overtrading costs you on your own price. Nothing is lost
  but rank.
- **The server decides.** game-core holds the four pools, the rivals and the events. The day's set of events comes from
  the server's daily seed, and each run's order from its committed seed. Ties go to whoever reached the score first.
  Bot tells: reacting to the warnings in under 150 ms run after run, or the same route to the tick. The pot and the
  payouts work as they do now.
- **Teaches.** After the run, the mentor names what you met, once: "Your own trades moved the dial: that's price
  impact." "You closed the gap between two stalls: that's arbitrage." The same thing the Uniswap pool does at the
  exchange, felt with your hands first.
- **UI.** Dials and lamps on the stalls (world). Clock, apples and "worth now" (what your basket would fetch at the
  best stall) in the island (plate). The Rush board in the hall, with the top 3 and your neighbours two above and two
  below (world). The pot in a glass jar by the board, its amount on a brass plaque (world).

### The Spice Run

The flagship. Four stops, one of them a real Uniswap swap.

- **Numbers.** 30 energy. Pays what the card says from the sponsor's escrow: the launch campaign pays 1.00 USDC, which
  is your 0.50 cargo back plus a 0.50 reward. The cargo advance is one per human, needs the Town Pass, and is repaid
  first from the delivery. Title Spice Runner, stamp `spice-run`, 1 ticket plus medal tickets.
- **1. Cargo, at the harbourmaster.** If your wallet holds the 0.50, he checks it and waves you on. If it's short, he
  advances it on an IOU slip: hold E to sign (a pen scribble, 0.8 s). The slip goes in your pocket and reads "You owe
  0.50 USDC to the Spice Run. Paid back first from your delivery."
- **2. The swap, at the exchange kiosk: the Scale.** A brass balance holds the pool's two sides, sacks of USDC against
  sacks of MANGO, so you see how big the pool is next to your 0.50. A split-flap board gives the quote in the
  protocol's plain words: "0.50 USDC buys about 9.07 MANGO. The pool keeps 0.30%. If the price moves, you'll still get
  at least 8.98 MANGO, or the swap won't happen." A sand-timer shows the quote's minute. Q flips it for a fresh quote,
  at most every 15 s, and its base shows when the next one is allowed. **Hold E for 0.6 s to pull the lever.** The
  swap goes to the chain with a pending tag on the lever. When it lands, the scale tips and the board shows what
  arrived against the quote: "Received 9.05 MANGO. The quote said about 9.07, at least 8.98." The sacks pour into
  your crate.
- **3. The carry (new).** A run from the kiosk to the Spice Merchant in the Market Hall. The crate rides on your
  shoulder and sways. Keep it level with the mouse while you walk; a bubble level on the crate shows the tilt.
  Sprinting doubles the sway. Gusts off the river are warned 1 s ahead by blowing leaves, and the market crowd bumps.
  Past 35° it falls: three sacks spill, and you scoop each one up (hold E, 0.7 s). Where the map allows, a riskier
  shortcut saves about 20 s.
- **4. Delivery.** Set the crate on the merchant's scale (E). The delivery goes to the chain. The needle settles as the
  contract checks you brought at least the quoted amount. The IOU slip tears in two if you had one, and a receipt
  prints the sum: cargo back, reward, advance repaid, what reached your wallet, and a link to the transaction.
- **Skill.** The carry. The swap itself is not a skill test, on purpose: it's real money, and it should be calm and
  clear.
- **Thrill.** Your first real swap: the lever, the scale tipping, what arrived against the quote. Then the wobble and
  the gusts on the way.
- **Failure.** A stale quote: the sand-timer flips itself and asks you to look again. The price moves more than 1%
  before the swap lands: the swap doesn't happen, nothing is paid, and the lever resets for another go with a new
  quote. A spill costs time, never the spice: the MANGO is already in
  your wallet. Dropping the quest keeps the plan's rule: an open advance comes out of later rewards.
- **Medal (the carry).** Gold: the route's walking time plus 15 s, with no spill. Silver: within twice that. Bronze:
  delivered. Tuned on the real route.
- **The server decides.** The swap from the chain (the Swap event by your account inside the quest window, as today),
  the delivery from the delivery contract, the advance and its repayment from the escrow. The carry's medal from
  game-core. You can only deliver standing at the merchant.
- **Teaches.** Swaps, the pool's fee, slippage and a minimum you accept, and a small loan paid back first.

### Paint Your Shop Sign

- **Numbers.** 20 energy. Pays the card (the launch campaign: 0.25 USDC) from the sponsor's escrow. Needs your name, so
  the Town Pass. Repainting later is free.
- **The game.** The sign painter by the Market Hall's door hands you a brush. Write your line on a slate (1 to 80
  characters, one line), and pick the paint: one of the five brand colours. Then letter the first word yourself on
  the plank: faint pencil guides show each stroke, and you hold the mouse button and trace. Slow and on the line gives
  a clean stroke. Too fast thins and drips; off the line smudges. The painter finishes the rest in your hand.
- **Skill.** A steady hand.
- **Thrill.** It's yours, in public, for good. Hold E on the rope to hoist the sign onto the sign wall in the Market
  Hall, where the town's latest signs hang, and the people nearby look up.
- **Failure.** A messy word costs the medal. A chain refusal changes nothing, and you paint again.
- **The server decides.** The record on your name (`RecordsSet`), as today. The neatness from game-core: the strokes are
  inputs like any other run.
- **Teaches.** Your name is yours. Its records are public, and nobody can paint over them.

### Hold the Line

- **Numbers.** 20 energy. Pays the card from the sponsor's escrow. Hold at least 1 of the sponsor's token for 3 days.
  3 balance checks at random times, the first when you take it. Title Steady Hand, stamp `held-the-line`.
- **The game.** A patience quest, not a reflex one. The old trader in the Market Hall takes you on. For three days the
  hall's big board shows the token's price, and your phone's quest page carries a brass nerve dial: how far the price
  has swung since you started, and each check stamped as it passes ("Checked: held"). Nobody knows when the next
  check comes. On big down days, people in the square talk about selling. That's pressure as story, never a fake
  offer.
- **Skill.** Not panicking.
- **Thrill.** Real swings with something real at stake.
- **Failure.** Selling below 1 token fails the quest (`QuestFailed`), with no pay and the energy gone. This is the one
  quest where failing is the lesson, and the mentor names it: selling in a panic.
- **The server decides.** Balance checks on chain at random moments (as today).
- **Teaches.** Volatility, and that holding through it is the hard part. Never a promise of profit (the plan's rule on
  sponsors).
- **Open.** The template assumes you already hold the token. See Questions.

### The Town Pass

Not a game, on purpose: proving you're one real person shouldn't be a minigame. It's a ceremony.

- **Numbers.** 0 energy. Pays the card if a campaign funds it (0.20 at launch), and everything you're owed is paid at
  once.
- **The scene.** At the town hall desk, the clerk asks for your ferry ticket. World ID runs in the page, inside IDKit's
  own window, with the desk behind it. No separate browser window now. When it's done, hold E to bring the stamp down:
  TOWN PASS across your ticket, and the full milestone blast (the `town_pass` first). Your name is lettered on in ink:
  `sam.tallyport.eth`. The envelope behind the clerk is handed over, and a receipt prints for each payment.
- **Thrill.** The stamp coming down, the full blast, and the envelope of everything you've earned so far.
- **Failure.** A refused proof: "That didn't go through. Try again." A World ID that already holds another name: "That
  World ID already has a pass, for another name."
- **The server decides.** The proof, one human one pass, and the name, as today.

### Errand: The Unload

Your first job. The ferry's cargo, a crane and a cart.

- **Numbers (all four errands).** 10 energy. Pays today's errand rate from the house's fixed bucket. 3 a day, offered
  from the four errand games. 1 ticket plus medal tickets. Free practice at the spot.
- **The game.** The crane's hook swings a crate over the cart. Space lets go. Crates stack under real physics. E sends
  the cart off with its stack: those crates are banked. The job is 12 banked crates. A cart trip takes 4 s, so tall
  stacks are quicker, but a stack that sways too far topples, and the crates on it that weren't banked go into the
  harbour. A flag on the crane shows the wind 1 s before it pushes the swing.
- **Skill.** Timing the swing, and judging how high to go before you bank.
- **Thrill.** The tower creaking, one more crate or send it now.
- **Feedback.** A deep thunk for a crate dropped dead centre (within 10 cm), a lighter one otherwise, a creak as the
  stack sways, a crash and splashes for a topple.
- **Failure.** A topple loses what wasn't banked, which costs time. The ferry always has more cargo.
- **Medal.** Gold within 1:20, silver within 2:00, bronze done.
- **The server decides.** Physics in game-core, with Rapier in cross-platform determinism mode, so the server's
  simulation matches the browser's to the bit. Inputs: the ticks you let go and sent the cart.
- **Teaches.** Lock in your gains: what's on the cart is safe, what's on the hook isn't.

### Errand: The Post Run

- **Numbers.** As every errand: 10 energy, today's errand rate from the fixed bucket, 1 ticket plus medal tickets.
- **The game.** The harbourmaster's post sack: 14 letters for 10 doors along a route through the Homes and the square.
  The next letter comes up in your hand, its envelope big at the lower left. Run the route. A brass slot glints when a
  door is in range (2 to 6 m). Aim with the mouse and left click to throw. Four of the letters are scams: a sender
  spelled almost right, a red URGENT stamp, "confirm your wallet's secret words" on the back, a name that isn't
  quite the resident's. Right click bins a letter.
- **Skill.** Aim on the move, and reading fast.
- **Thrill.** Speed, clean throws in a row (the clack steps up in pitch), and a lit window for each hit.
- **Failure.** A missed throw flutters to the ground and glows faintly until you pick it up. Post a scam and the
  resident comes out with it: "This is asking for my wallet's secret words!" That caps the run at bronze.
- **Medal.** Gold within 1:10 with no scam delivered, silver within 1:40, bronze done.
- **The server decides.** Which letters are scams, the throws and the slots, all in game-core. The browser gets each
  envelope's words to draw, never a flag saying which are scams.
- **Teaches.** Spotting a scam: nobody real asks for your secret words, and names matter.

### Errand: The Weigh House

- **Numbers.** As every errand: 10 energy, today's errand rate from the fixed bucket, 1 ticket plus medal tickets.
- **The game.** The Market Hall's big scale and a slate of 8 orders, each a weight. Hold Space to open the hopper:
  grain pours, faster the longer you hold (up to three times as fast). Let go and grain already in the air still
  lands, about 0.3 s of it. Stop the needle inside the band (2% either side).
- **Skill.** Anticipation: letting go before the needle gets there.
- **Thrill.** The needle creeping to the line. The bell when it stops inside.
- **Feedback.** The hiss of the grain rising with the flow, the needle's tick, a bell for a true weight, the thud of a
  tied sack.
- **Failure.** Under the band: the customer won't take it, so top it up. Over: the extra is given away. The slip at the
  end says how much of the stock you gave away.
- **Medal.** Gold: under 1% given away, within 70 s. Silver: under 3%. Bronze: done.
- **The server decides.** The flow in game-core. Inputs: when you held and when you let go.
- **Teaches.** Margins: small overfills add up.

### Errand: Lamplighter

- **Numbers.** As every errand: 10 energy, today's errand rate from the fixed bucket, 1 ticket plus medal tickets.
- **The game.** Dusk on the waterfront: light 12 lamps before night falls (100 s). The run borrows the evening look and
  eases it toward night as the clock runs down; the city's own time isn't touched. Hold E at a lamp to climb and light
  it (1.2 s). Your can holds oil for 8 lamps, and the oil store is in one place, so when to go back for more is the
  decision.
- **Skill.** Planning a route, and timing the refill.
- **Thrill.** The dark coming in around you while the lit lamps pool light on the paths and people come out onto them.
- **Failure.** Night falls with lamps unlit: try again tonight, with no more energy.
- **Medal.** By time to spare: gold with 20 s left, silver with 5 s.
- **The server decides.** The route, the oil and the clock in game-core.
- **Teaches.** Plan your spending: running dry halfway costs more than a planned stop.

### The Daily Mystery

A detective case, one a day, about 10 to 15 minutes.

- **Numbers.** 50 energy. Pays today's mystery, printed on its card: 0.50 USDC from the house's surprise bucket, or a
  sponsor's boosted pot up to the plan's 5.00. 1 ticket plus medal tickets.
- **The game.** Today's case is a card on the Bounty Board. Three leads, in any order:
  - **Examine.** A scene: hold the right mouse button to look closer, click what's odd. What you find becomes an
    evidence card in your notebook.
  - **Question.** A resident gives a statement, line by line. Press on a line for more. A contradiction becomes
    evidence.
  - **Tail.** Follow a suspect through town. Stay within 20 m and out of their sight cone. Use the stalls and the
    crowds as cover. Two seconds in their sight, or 30 m behind, and they slip away, and the tail starts again.
  - **The Reveal.** In the square, with a crowd gathered, the culprit testifies line by line. When a line contradicts
    your evidence, open the notebook and present the card (E). Right: the line breaks, the camera punches in for 0.2 s
    and the crowd reacts. Wrong: you lose one of three hunches.
- **The cases are money crimes:** a rigged scale (unit prices and honest weights), the too-good savings club that pays
  old members with new members' money, the double invoice, price gouging (only on drought days), the fake pass seller,
  and the stall that talks its goods up and sells at the top.
- **Skill.** Deduction, and the tail's stealth.
- **Thrill.** The tail, and the moment a lie breaks.
- **Failure.** Lose all three hunches and the case goes cold until tomorrow. Your leads stay, and you can try the Reveal
  again tomorrow with no more energy. The pay never changes; the medal goes by hunches left.
- **The server decides.** Each player's case comes from the day's case and a seed of their own: who did it and where
  the evidence lies differ between players, so answers can't be passed round. The browser never holds the answer. It
  learns each clue when it's found, sends the accusation, and the server says right or wrong. You must be at each
  lead's place.
- **Cast.** The town's residents play the suspects (see Questions).

### Grandma's Ledger

Once a season. Her three pages, then her strongbox.

- **Numbers.** 50 energy. Pages in any order, the strongbox last. The strongbox holds 1.00 USDC from the house's surprise
  bucket, 5 tickets, the title Grandma's Heir and the `grandmas-ledger` stamp.
- **Page one, the paper.** Only on a day with a shock (festival, harvest or drought). The Tally's small ads carry a line
  in Gran's cipher, keyed by the day's headline. Turn the cipher wheel printed on the page until it reads, and it
  names a place in town, a different one for each player. The page lies there.
- **Page two, the bank clerk.** The clerk opens Gran's drawer in the vault: a combination dial. The numbers are hidden
  in her letter and in the clerk's records, and differ for each player. Drag to set each number, then pull the
  handle: the server says whether it gives.
- **Page three, three meals you pay for.** As the plan has it. The page is under the third plate, and the market board
  marks your three meals on the price line: you are part of the market.
- **The strongbox.** At your door. The three pages fit together on the lid and the lock turns: the full blast.
- **Skill.** Two puzzles, the cipher and the dial, and catching a shock day for page one.
- **Thrill.** The vault's quiet and the handle giving; the strongbox at the end of a week.
- **Failure.** A wrong try at the cipher or the dial costs only time. Pages you've found stay found until the season
  ends.
- **The server decides.** As today, plus the cipher's answer and the dial's combination, which the browser sends as
  tries and the server checks. The paper page only on shock days (`NotAShockDay`).
- **Teaches.** One money lesson a page, from Gran's forty years.
- **Open.** Its story is set in "Mumbai's old market", and page three asks you to spend. See Questions.

---

## Part 3. Chests, streaks and the other reasons to come back

### The rules

Random rewards are paid only from the surprise bucket (sponsor fees, sponsor drops and yield), never from what players
spent. Chests are never sold. The pity rule holds: the 10th chest without a golden drop has one, or a meal voucher if
the day's drops are gone. The server draws every outcome before the browser plays it, so skipping or editing the
animation changes nothing. Golden drops need the Town Pass; until then they're held for you.

### The chest at your door

When it's ready it glows warm, with dust in the light and a slow breath of 4 s, never a pulse. Walk up:

| Time | What happens |
|---|---|
| 0.0 s | Hold E for 0.5 s: the latch lifts with a click. |
| 0.5 s | The lid swings up (0.45 s, a slight overshoot), and light spills out in the tier's colour. The camera eases 0.6 m closer (0.6 s). |
| 1.0 s | Energy rises as a glow and flies to your face ring, which fills (0.4 s). |
| 1.35 s | Tickets flutter into the ticket roll in your pocket bar, and its count steps up. |
| 1.7 s | A meal voucher token, if there is one. |
| 2.05 s | A golden drop, if there is one: the light turns gold, a low bell, and the drop falls into your hand while the wallet's USDC rolls up. |
| about 3 s | The lid settles and the camera goes back. Any key skips to here. |

The chest's contents at launch (`rules.toml`):

| Tier | Energy | Tickets | Meal voucher | Golden drop (0.05 USDC) |
|---|---|---|---|---|
| Wood | 10 | 1 | 1 in 10 | 1 in 20 |
| Brass (a 3-day streak) | 20 | 2 | 1 in 4 | 1 in 10 |
| Gold (a 7-day streak) | 30 | 3 | 1 in 2 | 1 in 5 |

### Pity you can see

Ten rivets ring the lock. One lights for each chest since your last golden drop (`chest.pity`). When nine are lit,
the tenth is already gold before you open it: you know the next one has a drop, or a voucher if today's drops are
gone, and it says so. When a drop comes, the rivets go dark one after another.

### The odds plate

A brass plate on the chest's side. Hold E on it to read the table above for your chest's tier, and the pity rule, in
plain words.

### The chest grows with your streak

Come 3 days running and brass bands appear on your chest the next time you see it. At 7, gold. The week the Town Goal
is reached, it's one better, with a lantern hung on the handle to show why.

### The weekly strongbox: payday

Beside the chest: an iron strongbox with seven notches on its lid, one cut for each day you came this week. At 5 of
7, hold E for 1 s to turn the key (a heavy clunk). It isn't random: it's the streak bonus from the fixed bucket, so it
feels like payday. A pay slip comes out with 0.25 USDC, and 3 tickets and 30 energy with it.

### The daily slate (proposal)

A chalk slate by your door: today's chest, the free thali, errands 0 of 3, the mystery, Rush runs 0 of 3, the Price
Call. Chalk ticks appear as you do them. It reads only from `you`, and the phone's Town page shows the same.

### The weekly draw: Draw Night

Tickets are earned, never bought. A brass drum stands in the square all week, with the prize on a board beside it.
When the week closes, the drum is sealed with wax (`DrawCommitted`) and the board shows the tickets in it and the
prize: 5% of the surprise bucket. Ten minutes later it spins for everyone in town (`DrawRevealed`), and the winning
number turns up on the board. The feed names the winner, never the amount. For the winner it's the full blast.

### The Town Goal lanterns

A string of lanterns crosses the square, one for every 20 meals of the week's 200. Each lights as the town eats. When
the last one lights, everyone's next chest is one tier better, and the square stays lit for the night. See Questions:
today it counts only meals bought on chain.

### Market Rush pay-out

At the real day's close, the hall's board turns over to today's top 10, and each of them gets a pay slip
(`RewardPaid`, or held without the Town Pass). The pot's jar empties, and the feed says who topped it.

### Medals and the passport

Your ferry ticket, stamped as the Town Pass, opens into a passport (P), and anyone can open yours from your name tag:

- the front: your name, your ENS name, your title and your shop sign;
- the stamp pages: one stamp for each quest done (the same stamps written on your name), with the best medal you've
  won in each game embossed beside it;
- your firsts, your reputation (Known around town and the rest) and your days in town.

Filling a page earns a title. Proposed titles: **Hall Trader** (a day's Market Rush top 10) and **Sharp Eye** (ten Post
Runs with no scam delivered). Titles go on your name like the ones today.

### Ghosts

After your first run of any game, your best run rides along as a ghost. In Market Rush, today's leader can ride along
too. Racing a ghost is the cheapest thrill there is, and the inputs are already stored for checking runs.

### Neighbourly (proposal)

When someone's rescue meal is on its way (`RescueComing`), any player nearby with the Town Pass can carry it: "A plate
needs taking to a door at the Homes." The carrier never learns whose door, or why: being broke stays private. The
safety net still pays for the meal, the carrier gets 1 ticket (once a day), and the one rescued sees who brought it.
If nobody picks it up within 90 s, or the carrier isn't there within 8 minutes, the neighbour brings it as now, so the
plan's 10 minutes always holds.

### Sponsor weeks (proposal)

A sponsor can fund a week of better chests: their banner on every chest, and golden drops more likely, paid from their
own money into the surprise bucket as a sponsor drop. The odds plate shows the week's odds and who is paying for them.

### The Price Call

At the chalkboard in the square: hold the mouse button and flick up, across or down to chalk your call, with a chalk
squeak. When the next city day opens, the board's numbers flip: a right call earns 2 tickets, and the feed says so.

### How big each moment gets

| Size | Moments | Treatment |
|---|---|---|
| The full blast | the Town Pass, your first quest done, Grandma's strongbox, winning the draw | Full screen in the green colourway: rays, shockwave rings, confetti, the title stamping in with a shake and a shine, the counters. The only place the game does this. |
| A moment in the world, under 3 s | the chest, a golden drop, the strongbox, a swap landing, a medal, a cold case cracked | Physical: lids, light, paper, a short camera ease, a bell. Skippable. |
| Quiet | tickets, a login, a right Price Call, a meal eaten, a first meal | A lobe from the island, or the small first note under the clock. |

### What's never in the game

No buying chests, keys or odds. No paid boosts or energy refills beyond meals at the live price. No countdowns made up
to hurry anyone. No wheel to spin for USDC. Nothing in the feed about what anyone paid, earned or holds. And the
streak forgives: it's 5 days of 7, not every day.

---

## Part 4. The HUD and every UI element

### The look

- **Plates** are ink `#262727` with a 3 px cream `#FFF8E3` outline, and only where words sit on the moving world.
  Everywhere else: type on the scene, or real things such as boards, chalk, paper and dials.
- **Colours,** from `DESIGN.md`: blue `#0011FF` for USDC (always with the dollar sign), green `#337E43` for keys and
  success, magenta `#E100FF` for name tags, orange `#FF6600` for warnings and refusals. Black text on magenta and
  orange; white on blue, green and black. Gold `#F0C33A` is in the Figma with no stated job: TODO, see Questions.
- **Fonts,** from `D:\code\Godot\dhaniverse-v2\apps\web\public\font`: Satoshi for words, and Satoshi Bold for money,
  because Bitroad's slashed zero made "100" misread. Bitroad, the stand-in for PP Mondwest, for keycaps, run counters
  and big moments. Instrument Serif, the stand-in for PP Editorial New, for paper: letters, tickets, receipts, The
  Tally and menus.
- **Logo:** `brand-mark.svg` and `brand-wordmark.svg` in `D:\code\Godot\dhaniverse-v2\apps\web\public\`. Never redrawn.
- **Scale:** every screen is laid out in a 1440×810 design space in rem (html font size = 10 × min(100vw/1440,
  100vh/810)), and fits 810 tall.
- **Motion:** everyday UI gets fades of 0.15 to 0.3 s, mask reveals and counters that roll over 0.4 s. No shake, no
  spinning beams, no marquees, no pulsing. Things in the world move as things do: lids, paper, needles. The
  milestone blast keeps everything.
- **Sound** is generated in the browser like today's sounds. Paper, bells and money landing come first.
- **Built with:** plates, paper and the phone in React over the canvas. Things in the world drawn by three.js, as part
  of the scene.

### Where everything lives

**World** is drawn in the scene on a real thing. **Tag** is pinned to a thing in the world and drawn over it.
**Plate** is a dark plate on the screen. **Paper** is a paper thing held up to the camera. **Phone** is on the phone.
**Screen** covers the screen.

| Element | Lives | What it shows, from the server | Motion |
|---|---|---|---|
| You | Plate, top left | Your face with the energy ring, your name (your ENS name once you have one), energy pips, "+1 in 2:41" under 40, and when the free thali is ready (`energy`, `energy_regen_at`, `free_meal_at`, `ens`) | The ring fills over 0.4 s; pips light left to right |
| Wallet | Plate, under You | USDC, what's owed and why, the Town Pass stamp, a pending stamp while something is at the chain (`usdc`, `pending_rewards`, `human`, `meal_pending`) | The counter rolls over 0.4 s |
| Rehearsal mark | Plate, under Wallet | "Rehearsal town: the money isn't real", only when `city.chain` is `offline` | none |
| The island | Plate, top centre | The city day and time with the sun dial; one event at a time as a lobe; during a run, its clock, score and medal marks | A lobe opens over 0.5 s |
| Minimap | Plate, top right | About 90 m round you, north up, a gold marker for the next step, the place name under it | none |
| Dialogue | Plate, bottom centre | Who speaks and the line; in films it sits on the lower bar | A fade |
| Pocket bar | Plate, bottom centre | Phone, passport, notebook, ticket roll (count), meal vouchers (count), the quest item (an IOU slip, the post sack). Keys 1 to 6. Full when something changes or a key is pressed, a slim row otherwise | A slot lifts when used |
| Mentor | Plate, right, under the minimap | One line after something real happens; H opens the chat | A fade |
| Link notice | Plate, top centre | "Can't reach the town. Nothing you do counts until it's back." | none |
| First note | Screen, under the clock | A small first, with a little confetti | 1.5 s, quiet |
| Run cards | Paper | Before a run: the medal times and the keys. After: score, medal, best, rank, and what you met | Printed, held 3 s, pocketed |
| Key hints | Tag | A green plate with a tail: "E Open your chest", "Hold E Tear it off". With no key, a dark plate for a remark | Pops in from 0.8 scale |
| Name tags | Tag | Name and title over players, on magenta. Click one for their passport | none |
| Pending stamps | Tag | "At the chain" on the lever, the scale or the sign while a transaction waits | A stamp lands |
| Price tags | Tag | Over each dish at the Common Table: the live price in USDC and its arrow since yesterday | Split-flap flip |
| Bounty Board | World, Tally Square | A card per quest: who pays, the energy, the USDC, places left, and an "on Arkiv" pin. Hold E to tear one off | The card tears and flips into your hand |
| Market board | World, Tally Square | The live food price and seven days of it from Arkiv, today's open, any shock | Split-flap ticks |
| Price Call board | World, Tally Square | Today's price, your chalked call, the result | Chalk strokes |
| Common Table | World | The menu board with live prices, the till that prints meal tickets, the community pot for the free thali | A printed ticket |
| Pantry (proposal) | World, the Common Table | The food pool's stock as crates on shelves, filling when the farm sells and emptying as the town eats | Crates appear and go |
| The exchange | World, the landing | The Scale, the quote board, the sand-timer, the lever | The scale tips |
| Spice Merchant | World, Market Hall | His scale; the needle settles on delivery | The needle |
| Your door | World, the Homes | The chest (tier, rivets, odds plate), the weekly strongbox (notches), the daily slate | The lid, the key |
| Town hall desk | World | The clerk, the stamp, the envelope of what you're owed | The stamp |
| Sign wall | World, Market Hall | The town's latest shop signs, yours among them | A sign is hoisted |
| Quest markers | World | Gold diamonds over each place a step needs | none |
| Market Rush | World, Market Hall | The four dials and lamps, the Rush board (top 3 and your neighbours), the pot jar | The needles |
| Errand props | World | The post sack and door slots, the crane and cart, the Weigh House scale and slate, the lamps and the oil store | Physical |
| The Wall | World, Tally Square | Firsts carved by name; hold E to carve yours | A carving |
| Town Goal | World, Tally Square | The lantern string | A lantern lights |
| Draw drum | World, Tally Square | The tickets in it, the prize, the seal, the winning number | It spins on the reveal |
| Rescue | World | The neighbour (or a player) walking up with a plate | none |
| Ferry ticket and passport | Paper (P) | Your name, the stamp, your stamps, medals, firsts, sign, reputation | Pages turn |
| Gran's letter | Paper | Her letter; it's kept in the passport's cover | none |
| Receipts | Paper | Every money moment: a meal, a pay slip, a held reward, a swap, an advance, with a link to the transaction. Pending until the chain confirms | Printed, then to the wallet over 0.3 s |
| The Tally | Paper (N) | The morning paper, written by the server | none |
| Quest cards | Paper | A torn card read in your hands, then kept in the pocket | none |
| Notebook | Paper | A mystery's evidence and Gran's pages | Cards slide |
| IOU slip | Paper | What you owe on an advance | Tears when repaid |
| Phone | Phone (Tab) | Feed (with reactions), Quests (your cards and steps, drop one), Wallet (address, receipts with links, vouchers, the pass), Town (the goal, the draw, the Rush pot and board, the Price Call, who sent you) | It comes up into your hand |
| Mentor chat | Plate (H) | The mentor's lines and your questions | Types out |
| Title | Screen | The wordmark and the menu over the live town | Fades |
| Milestone blast | Screen | The full blast | Everything |
| Settings | Screen (Esc) | Sound, camera, motion (big moments full or calm), text size, keys. The shot holds, the bars close in, and the choices sit in shadow on the right | Fades |
| World ID | Screen | IDKit's own window, over the desk scene | IDKit's |
| Sign in | Screen | The wallet's passkey prompt, on a new device | the system's |
| Can't start, load failed, GPU reset | Screen | A plain message with retry or reload, on the brand's black | none |

---

## What the server needs

Proposals; the builder settles their shape. Everything else above uses protocol v3 as it is.

| Need | For | Shape |
|---|---|---|
| A run session | every skill game | `StartRun {game, quest, step}` gets `RunStarted {run, seed_hash, ends_at}`. Inputs stream as `{"type": "run", run, tick, inputs}` every 100 ms, like `move`. World events arrive ahead of time as `run_event`, and the lead is the in-game warning. The end is `RunEnded {run, score, medal, seed}`, or `RunHeld {run}` |
| A `run` step kind | quests with a game inside | `{kind: "run", game, medals}` in `quests.toml` |
| Market Rush on runs | the trading sprint | `StartRush` starts a run; `ServeOrder` and `most_orders_per_run` go; `served` becomes `score` |
| Medals | every game | Best medal per game in `you`, and `TicketsEarned` with `why: "medal"` |
| The mystery | the detective case | `Examine {quest, lead, spot}` gets `EvidenceFound`; `Present {quest, line, card}` gets `LineBroken` or `HunchLost {left}`; `CaseCold {until}` |
| Puzzles | Grandma's Ledger | `Solve {quest, step, answer}` gets `QuestStepDone` or `WrongAnswer` |
| Ghosts | Market Rush, errands | `GET /ghost/<game>`: today's leader's inputs, seed, name and title |
| Pool sizes | the Scale and the pantry | The pools' reserves in `city.food` and on `SwapQuoted` (public on chain anyway) |
| Sign colour | the sign painter | `PaintSign {text, colour}`, one of the five |
| The sign wall | Market Hall | The town's latest signs with their names in `city` (public on ENS anyway) |
| The first job | newcomers | The Unload offered to anyone who has never done an errand, even on a day it isn't on the list; it counts as one of their three |
| Neighbourly | carried rescues | `CarryRescue` gets `RescueCarried`; the resident still comes if nobody does |

---

## Calls made after the builder check (check these)

- **When the day's allowance runs out.** The technical plan says pools spend a share of what they hold, never a fixed
  promise, and the server pays at most what's left of a bucket. So every paid card shows its amount and the paid
  slots left today. A sold-out quest says so and when it refills, and refuses before any energy is spent. A few of
  each day's errand slots are kept for players doing their first job, so the first pay slip always happens. The
  strongbox and the odds plate show what's left in today's allowance. The pity rule falls back to a meal voucher, as
  the plan says, and if the voucher money is gone too, to the energy itself, granted directly as the rescue meal's
  last resort does. It never falls back to nothing.
- **Held runs and the Market Rush pot.** Only players with a Town Pass rank for USDC. Players without one still see
  their place, marked "not ranked for pay", and the next verified player takes the slot. A run the server holds is
  left out of the paid ranking automatically. Its player sees "under review, not counted today", and the replay is
  kept. The pot pays at close without waiting. Operators get a pause switch per game. A human review screen comes
  later, if appeals need one.

## Questions for the founder

From the builder check, the two that matter most:

A. **Who holds a player's keys, and how does a player get back in on a new device?** Today one server seed derives
   every player's key and the server signs everything, so one secret controls every player's USDC, and a player who
   loses their browser data loses their name, wallet and Town Pass for good. The technical plan asks for an embedded
   ERC-4337 smart wallet. The recommendation: each player gets a smart account whose owner is a passkey made in their
   browser (no seed phrase, nothing to write down). The server holds only a session key limited to the game's
   contracts and daily caps, so meals, swaps and records still happen without a prompt, and the paymaster pays the
   gas. Recovery is the passkey syncing through the phone's or laptop's keychain, plus World ID re-verification to
   move a name to a new passkey. It also keeps the Paint-Sign lesson true: nobody, not even the server, can paint over
   your name.
B. **How big is the launch, and must the city survive updates?** The server is planned for about 30 players at once
   on one CPU, while the plan's economy example uses 1,000 players a day. And today any rule change makes an old save
   refuse to load. The recommendation: plan for 200 players at once at the event, one server near the event, and
   cities that may reset until launch, with versioned saves after it. Where the server runs is your call, since you
   host dhaniverse.com.

From the design itself:

1. **Meal names and "keep it global."** The plan's meals are chai and biscuit, vada pav and thali, with the free
   community thali, the rescue thali and thali vouchers. The errand "The Chai Round" has a chai wallah, and Grandma's
   Ledger is set in "Mumbai's old market". Keep them as the plan has them, or rename them? The numbers don't change
   either way.
2. **Market Rush as the trading sprint,** with apples as the run's score, never spendable and never carried out of the
   run. Yes?
3. **"Skill earns medals, not money":** quests that cost energy pay a fixed amount, and medals pay tickets (gold +2,
   silver +1). Yes?
4. **The Town Goal counts meals bought on chain,** so spending is what makes everyone's chest better, which sits close
   to the plan's line on random rewards. Count every meal, the free thali included, or finished quests instead?
5. **Hold the Line:** how does a player get the token they must hold? A buy step at the exchange, an advance like the
   cargo, or only for players who already hold one?
6. **Grandma's Ledger page three** asks the player to pay for three meals. Keep it as the plan says?
7. **Sound needs a key press in browsers.** "Press any key" after the logo, before the ferry. All right?
8. **Leave on the title menu** can't close a browser tab. Drop it, or make it "Back to dhaniverse.com"?
9. **Names.** This adds nobody new. The roles stay unnamed (the harbourmaster, the clerk, the sign painter, the old
   trader, the exchange keeper, the Spice Merchant). Do you want any named? We'd propose a few for you to choose from.
   The mysteries give the 20 residents in `rules.toml` speaking parts (Asha, Bilal, Chen and the rest): have you seen
   those names? And are the people in the landing page's art the game's cast?
10. **Proposed titles:** Hall Trader and Sharp Eye (Part 3). Keep, rename or drop?
11. **Gold `#F0C33A`** has no stated job in the Figma. Use it for the gold chest, gold medals, the pity rivets and quest
    markers?
12. **Money's font:** the HUD uses Satoshi Bold for money; `DESIGN.md` still proposes the pixel face. Which?
13. **New mechanics:** ghosts of today's Market Rush leader (their route, name and title, seen by everyone), Neighbourly
    rescues, sponsor weeks for chests. Which do you want?
14. **The Figma export holds only the landing page.** Are there HUD, chest or game frames in `Dhaniverse.fig` to export?

## What this was built from

- Read in full: `docs/planning/Dhaniverse_Technical_Plan.html`, `docs/planning/Web_Client_Design.md`,
  `server/PROTOCOL.md`, `server/rules.toml`, `server/quests.toml`, `DESIGN.md`, and your standing rulings on the HUD,
  the opening, the world, the brand, names and dates.
- Read as the reference to replace: `game/scripts/world/` (the opening, harbourmaster, Bounty Board, price board, door
  chest, Spice Run, sign painter, Town Pass desk) and the headers of every script in `game/scripts/ui/` and
  `game/scripts/market/`, with the stall's code in full. Checked in the server: the chest's pity rule and which meals
  count toward the Town Goal.
- The Figma export: the frame list and every text layer of `landing.json`, five images at 360 px, and the brand sheet's
  thumbnail. It holds the landing page, the waitlist and the header, with no HUD or chest frames.
- `docs/design/research_game_feel_and_retention.md` for the evidence on onboarding, boards and feedback.
