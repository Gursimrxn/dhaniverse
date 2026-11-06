# Code Map: what the game layer actually does today

Written by reading the code, not by running the game. Where I am not sure I say so ("inferred", "not checked").

How to read the references:

- `file:line` is relative to `game/scripts/` unless it starts with `server/` or `game/`.
- `game/scripts/valley/world.gd` is being edited by another agent right now (performance work), so its line numbers may drift by a few lines. All the others were stable when I read them.
- "The bot" means `game/dev/tallyport_drive.gd`.
- The planning docs (`Game_Layer_Design.md`) describe a different, richer game than the one in the code. Where they differ, this map says what the code does.

---

## 0. The ten facts that matter most

1. **The build is the "Valley" world with a server-driven game layer bolted on.** The entry is `main.gd` which loads `valley/world.gd`. The whole layer (HUD, client, opening, boards, stall, chest, phone) is built in one function, `_market()` (`valley/world.gd:1361`). The older "Old Quarter" world (`world/world.gd`, 2092 lines) is dead: `--world=quarter` points at `world/quarter/world.json`, which does not exist.
2. **Identity is a name plus a random secret kept in `user://settings.cfg`.** There is no wallet sign-in, no passkey, no World ID at login. World ID appears only later as the "Town Pass", through a one-time browser link, and it needs an existing player with a wallet. A "World sign-in at the gangway gate" cannot be built on the current protocol (section 8.1).
3. **New players get no goal.** After Gran's letter the only guidance is a 7 second subtitle ("Kofi at the Market Hall could use a hand, past the bank", `world/opening.gd:34`). There is no quest, no marker, no minimap goal, no checklist. The first gold marker appears only after the player takes a quest at the Bounty Board.
4. **Guidance is thin and mostly invisible.** Key hints for the world fade after four uses (except TownThings hints, which never fade). The always-on key list shows only Run, Rotate, View. Nothing names Tab (phone), H (mentor), N (paper), Esc (settings), or 1 to 5. The mentor knows exactly one lesson (inflation, after a dearer second meal) (`server/crates/agents/src/mentor.rs`).
5. **A new player who cannot reach the server gets silence.** `LinkNotice` never shows for a nameless connection (`ui/link_notice.gd:34`: `client.player == ""` resets its timer). On the web, `TownClient` falls back to `ws://127.0.0.1:7878` unless the iframe URL has `?server=` (`client/town_client.gd:24, 63-67`), and `apps/web/app/play/page.tsx` embeds `/godot/index.html` with no query string. So a web player with no server sees the ferry, the ticket, types a name, and nothing happens.
6. **The first 25 seconds of the title are mostly waiting (about 23 s from the end of the world build to a usable menu, about 7 s if the player skips).** The ferry ride is 22 s (`world/opening.gd:20`). The clock starts under the logo (`main.gd:21-24`), so about 3.3 s of it runs under the logo and about 5 s by the time the wipe ends. Any key skips it (`ui/title_screen.gd:413-417`), but the logo (3.3 s) and the burst wipe (1.7 s) cannot be skipped (`ui/boot_intro.gd` has no input code).
7. **The "reward" layer is thin where the founder wants it thick.** A finished quest is `QuestDone{reward:{usdc,tickets,title,stamp}}` and a one-line island moment. No sound, no flying prize, no rarity. Rarity exists only as the chest tier (wood, brass, gold), and that comes from the streak, not luck (`server/crates/rules/src/chest.rs`).
8. **The server trusts the client for gameplay.** `QuestStep` (talk, visit, paper, strongbox, cargo) is accepted anywhere. `ServeOrder` is counted with no link to the client's customers, capped at 40 per run (`server/crates/rules/src/rush.rs:39-68`). Rush pot money rides on those counts.
9. **Lots of dead or contradicting code.** Whole quarter-era folders, a scooter nobody can ride, a hidden toast and ticker, `Cast` lines for people who do not exist ("Asking Mei for the thali…" with no Mei in town), and the `--game` flag that adds door spots nothing consumes. Details in section 7.
10. **The walkthrough bot never touches the opening.** It passes `--player=drive1`, so it skips boot, title, ferry, ticket and name claim, and goes straight to the letter (section 1.7).

---

## 1. Boot to town, as implemented

### 1.1 What starts what

| Step | Where | What it does |
|---|---|---|
| Web shell | `game/web/shell.html` | A cream loading line (196 by 2 px at 720 tall), filled to 60% by the download, then `BootIntro` takes over its look. |
| Entry scene | `scenes/main.tscn` -> `main.gd:6` | Picks `valley/world.gd`. If `TitleScreen.wanted()` is true, builds a `BootIntro`, waits two frames, then builds the whole world synchronously in `_ready` (`main.gd:16-19`). |
| World build | `valley/world.gd:132-` | Lighting, terrain, water, town, street, grass, trees, flowers, player, post, then `_market()` (the game layer) and `_say_who()` as its last line. |
| Title | `ui/title_screen.gd` | Created inside `_market()` only if `wanted()` (`valley/world.gd:1478`). |
| Start-up of intro | `main.gd:21-24` | `world.title.begin()` runs first (puts the ferry at the start of its ride, locks the player, camera on the film shot), then `intro.opened.connect(world.title.enter)`, then `intro.play()`. |

`TitleScreen.wanted()` is false (no title, no logo skip is needed, the player is a bot or a capture) when: `skip_once` is set, or any arg starts with `--snap` or `--shots`, or is `--arrive`, `--no-title`, `--game`, or `--world=quarter` (`ui/title_screen.gd:52-57`).

### 1.2 The beats, in order (a person starting fresh, no saved name)

Times are from the code. Add real load time for the world build (not measured). I infer that the loading line's tween (`ui/boot_intro.gd:63`) cannot visibly run during the world build, because the build blocks the main thread inside `_ready`.

| # | Beat | Trigger | What the player sees and presses | Length | Code |
|---|---|---|---|---|---|
| 1 | Web loading line | page load | cream line on black, fills as the engine downloads | download time | `game/web/shell.html` |
| 2 | Black + line | engine starts | black screen, same line; no input | until world is built | `ui/boot_intro.gd:29-63`, `main.gd:10-19` |
| 3 | Logo | `intro.play()` | line finishes (0.25 s) and fades (0.2 s); the coin mark pops in spinning from -90 degrees (0.5 s); the word "Dhaniverse" opens beside it (0.6 s), holds (0.7 s), closes (0.6 s); the mark breathes (0.26 + 0.2 s) | about 3.3 s | `ui/boot_intro.gd:111-137` |
| 4 | Burst | end of logo | the town shows through the mark-shaped hole as it grows (wipe 1.7 s), a ring (1.1 s) and a flash (0.5 s peak). `opened` fires at the start of this beat | 1.7 s | `ui/boot_intro.gd:145-160` |
| 5 | Ferry film | `title.enter()` at `opened` | letterbox bars in (0.5 s), card "Tallyport" (fade 0.35, hold 3.3), the ferry rides up the river to the jetty at dawn. A small "Any key: Skip" legend fades in after 1.5 s. Camera: `Opening._film_shot` from across the water, slowly closing in | ferry ride is 22 s total, of which about 3.3 s ran under the logo and about 5 s by the end of the wipe; so about 17 s of it is left to watch | `ui/title_screen.gd:260-268`, `world/opening.gd:20-22, 138-141, 151-165` |
| 5b | Skip | any key or click once `_may_skip` | screen closes on the mark (0.9 s), ferry jumps to the jetty with the horn, screen opens (0.9 s) | 1.8 s | `ui/title_screen.gd:271-275, 413-417`, `world/opening.gd:116-121` |
| 6 | Title menu | ferry alongside (`alongside` signal) | after 0.5 s the "Dhaniverse" word fades up (1.1 s), then 0.3 s later the menu words roll in (0.6 s each, 0.09 s stagger), keys go live about 0.8 s after docking; a live-town plate (food price line, "N in town", day) and a scrolling news line fade in 0.8 s later. Keys: Up/Down or W/S choose, Enter/Space/E go | menu live about 22.8 s after start, or about 7 s after a skip | `ui/title_screen.gd:277-300, 413-424` |
| 7 | Choose | Enter on a word | "Continue" (only if a name is saved), "A new life", "Settings" (opens the settings panel over the title), "Leave" (`get_tree().quit()`, which does nothing useful in a browser) | | `ui/title_screen.gd:240-257` |
| 7a | Continue | | camera cuts back, screen wipes through the mark, plates fade in over 0.8 s, control returns. A returning player who never read the letter goes to the letter instead (step 12) | about 1 s | `ui/title_screen.gd:312-325`, `valley/world.gd:1543-1544` |
| 7b | A new life | | if a name is saved, asks once ("Press again. NAME stays in town."), then clears the saved name and secret and reloads the scene with `skip_once` set (no title, `Opening.play()` film). With no saved name: title fades 0.5 s and the game begins on the deck | 0.5 s | `ui/title_screen.gd:328-346` |
| 8 | Deck | `play_from_port` | bars out (0.5 s); camera glides from the title shot to the player's view (1.8 s); the player stands on the foredeck, controls live. The only teaching is a "W Walk" hint if the player stands still 6 s | 1.8 s | `world/opening.gd:106-113, 179-192` |
| 9 | Ticket | player walks past the deck's bounds: more than 3.5 m forward, more than 1.45 m sideways, or behind -0.2 m | the player freezes; the paper "ferry ticket" sheet opens (0.18 s): a line "Write your name" (lowercased as you type, 20 characters at most), a pill "Enter: That's me". Enter sends `ClaimName`. Orange note on refusal ("Someone in town already goes by that." or "Use 3 to 20 letters or numbers.") | player's pace | `world/opening.gd:188-193, 205-211`, `ui/ferry_ticket.gd` |
| 10 | Ashore | server answers the claim; snapshot arrives; `ticket.accept()` -> `named` | ticket closes, player walks off the ferry. If the ferry was still riding it now speeds up 2.5 times (`RIDE_NAMED`). The harbourmaster waves and calls "Over here, NAME!" as a subtitle every 9 s | player's pace | `world/opening.gd:213-219, 194-200` |
| 11 | Harbourmaster | player within 3.1 m of him | player freezes, bars in, a 9 s over-the-shoulder shot (not skippable). He says "Morning, NAME. I've something for you. From your gran." (2.8 s), hands over a sheet of paper (prop flies to the player's hand, `paper` sound) | about 2.2 s to the letter | `world/opening.gd:244-263`, `world/harbourmaster.gd:55-70` |
| 12 | Gran's letter | 2.2 s into step 11 | paper sheet: "Dear NAME, ... I tore the pages out and hid them around Tallyport ...", P.S. "Kofi at the market could use a hand. Tell him I sent you." Pill "E: Fold it away" (the key must have been released first) | player's pace | `ui/gran_letter.gd`, `ui/strings.gd:27-28` |
| 13 | Release | E | `read_gran_letter` is saved on this machine; harbourmaster subtitle "She was a good one, NAME. Kofi at the Market Hall could use a hand, past the bank." (7 s); bars out (0.5 s); camera lands (1.1 s); the dawn sky eases to day over 10 s | about 1.6 s | `world/opening.gd:270-285` |
| 14 | HUD fade-in | same moment | you plate, wallet plate, minimap, pocket bar, key list and island fade in over 1.4 s, starting 0.8 s after release | 2.2 s | `world/opening.gd:284`, `valley/world.gd:1440, 1468-1469` |

Everything else (the first-look flights into the bank, market hall, Common Table, courtyard and landing; the season ferry) is covered in section 5.

### 1.3 Other ways in

- **Crash or close after naming but before the letter:** `_say_who()` sees a saved name, connects with `client.start`, waits for the snapshot, then `opening.resume()` goes straight to the harbourmaster and letter (`valley/world.gd:1543-1544`, `world/opening.gd:238-241`).
- **Saved name the server refuses (`hello_refused`):** `Opening._on_hello_refused` reconnects nameless and opens a fresh ticket on the landing (`world/opening.gd:225-230`).
- **No title** (`--no-title`, bots, or after "A new life" / a quality change): `Opening.play()` runs its own 5.5 s film (bars, "Tallyport" card), then the deck (`world/opening.gd:90-103`).
- **A second window with the same name:** the old one gets `kicked`, stops retrying and shows "This town is open in another window." (`client/town_client.gd:237-240`, `ui/link_notice.gd`).

### 1.4 Command-line dev flags (all after `--`)

Skip or shape the boot:

| Flag | Effect | Where |
|---|---|---|
| `--no-title` | no logo, no title; world plays `Opening.play()` for a new player | `ui/title_screen.gd:55` |
| `--arrive` | no title; "trial" mode: the name and "letter read" are not saved; plays the full first-time film | `ui/title_screen.gd:55`, `valley/world.gd:1441, 1525` |
| `--player=NAME` | the client starts as that name at once (skips ticket and name claim) | `client/town_client.gd:54` |
| `--game` | no title; also builds the old door spots and the named cast (`_game()`) | `valley/world.gd:161, 1299` |
| `--snap=`, `--shots=`, `--title-shots=DIR`, `--title-skip` | screenshot capture modes; `_say_who` asks nothing | `valley/world.gd:164, 181`, `main.gd:25-53` |
| `--server-url=URL`, file `server_url.txt` beside the exe, web `?server=` | which town | `client/town_client.gd:55, 63-72` |
| `--no-browser` | print the Town Pass URL instead of opening it | `world/town_pass_desk.gd:72` |
| `--world=quarter` | loads the dead Old Quarter (broken, see section 7) | `main.gd:9` |

Look and performance (dev): `--mode=day|evening|night`, `--quality=low|high`, `--view=top|third|first`, `--season=`, `--render-scale=`, `--lod=`, `--no-msaa`, `--shadow-size=`, `--free-frames`, `--tree-near=`, `--height=`, `--off=town,water,street,grass,trees,flowers,post,market,port,cast,shadows,sky,hero,people,kiosks,counters,interiors`, `--hud`, `--probe=`, `--scan=`, `--stand=`, `--map=`, `--walk=`, `--cam=`, `--at=`. In-game dev keys: F1 test panel (rehearsal server only), F2 quality, F11 fullscreen, U render scale, Y season, T time of day, C camera view (`valley/world.gd:430-444`).

### 1.5 Persistence of the boot

Everything is in `user://settings.cfg`, section `graphics` (`valley/world.gd:263-273`): `player_name`, `player_secret`, `read_gran_letter`, `seen_<place>`, camera, quality, volumes, toggles. The secret is plain text there (made at `valley/world.gd:1526-1529`). Clear browser storage and the account is gone (no recovery path exists in code).

### 1.6 What I did not check

The ferry and jetty collision (whether you can walk off the deck at the gangway), the length of the real world build, and whether `OS.shell_open` from inside the iframe is allowed by browsers.

### 1.7 What the bot covers

`dev/tallyport_drive.gd` (403 lines): it uses `--arrive --player=drive1`, so it skips boot, title, film, ferry, ticket, name claim and walking. It checks, against a `--debug` server: arrival and the letter (`:96-103`), Town Pass link and rehearsal pass (`:112-128`), the Bounty Board and taking an errand (`:132-148`), a paid thali (`:150-171`), the free thali (`:172-184`), a Market Rush run to the bell (`:186-211`), the chest (`:213-223`), the errand steps (`:225-237`), a sponsor's Spice Run end to end including quotes, stale quote and swap (`:239-292`), phone pages Quests and Wallet (`:293-297`), the Price Call (`:310-317`), the sign painter (`:319-333`), Grandma's Ledger (`_grandma`, `:341-374`), and the rescue meal (`_rescue`, `:377-398`). It teleports the player to each thing and calls the thing's own functions. It does not test: boot, title, camera, walking, the ticket UI, the harbourmaster handover, phone pages Feed/Town/Me, mentor, paper, settings, Hold the Line, referral, draw, other players, or any look.

---

## 2. Onboarding and guidance today

### 2.1 How the player is told what to do next

| Channel | What it does | Where | Gap |
|---|---|---|---|
| Subtitles | The harbourmaster's lines, the opening, quest hints from `Tallyport.tell` (3.5 to 7 s, a dark pill low on screen, or on the lower bar in a film) | `ui/cinema.gd:132-160`, `world/tallyport.gd:100` | Gone in seconds; not repeated |
| Gran's letter and the last line | Names Kofi and the Market Hall; the letter says pages are hidden around town | `ui/strings.gd:27-28`, `world/opening.gd:34` | The letter promises pages, but Grandma's Ledger is an optional card at the Bounty Board that costs 50 energy; nothing connects the two |
| Key hints | A green plate with a tail over the thing in reach: "E Read the Bounty Board", "E Open your wooden chest". `TownThings` picks the nearest thing with a non-empty hint within its reach (about 1.9 to 2.8 m). Pops in 0.22 s | `world/town_things.gd:31-51`, `ui/key_hint.gd:60-100` | Only shows when you are already at the thing; the world gives no "go there" pull |
| Key hint fade | Hints that are not `always_words` drop their words after 4 showings per verb and show only the key | `ui/key_hint.gd:7, 60-70` | `TownThings` sets `always_words = true` (`world/town_things.gd:19`), so board and chest hints never fade; stall, food counter and opening hints do |
| Key list | Bottom right: Run (Shift), Rotate (Z X), View (C), read from the real bindings | `ui/game_hud.gd:21, 296-329` | No move keys, no E, Tab, H, N, Esc, 1 to 5. No M map (the key is free) |
| Pocket bar | Five icons, keys 1 to 5: wallet, quests, feed, town, mentor. It is a phone launcher, not an item bar | `ui/game_hud.gd:19, 153-213, 283-293` | Names show on hover only; Tab is never shown |
| Walk hint | "W Walk" over the player after 6 s still on the ferry deck, then never again | `world/opening.gd:184-191` | The only controls teaching in the game |
| Minimap gold marker | A gold dot, pinned to the rim with a ping ring every 2 s when off the map. Set by `QuestMarks._goal()`: the first quest whose next step has a known place | `ui/minimap.gd:142-152`, `world/quest_marks.gd:222-235` | Points at one place only; set only when `you` changes (a roaming harbourmaster is a stale point); nothing before the first quest |
| World markers | A spinning gold diamond (1.6 rad/s, bobbing 0.12 m, 2.5 m up) over **every** place that has an open step, including chain steps (swap, deliver, sign, verify). Scale 0.75 while waiting for the chain | `world/quest_marks.gd:30-48, 126-135` | No label, no distance fade, not a single tracked quest |
| Phone, Quests page | Each quest, steps ticked with `[x]`, `[..]`, `[ ]`, and a gold "Next: place" line using `PLACE_WORDS` | `ui/phone_quests.gd` | You must open it; no tracking choice |
| Mentor | One server line ("Same meal, more money...") appears as an island moment (8 s) with "H Ask"; H opens a chat with three fixed prompts plus free text | `ui/mentor_chat.gd:24, 293-320`, `ui/island.gd:265-268` | Server knows one lesson; the free-text answer is a lookup, no model (`server/crates/agents/src/mentor.rs`) |
| First notes | Small "A NEW FIRST" line under the clock with 26 pieces of confetti (3.2 s), only for `first_meal`. `first_quest` and `town_pass` get the full 4.5 s blast | `ui/first_note.gd`, `ui/milestone_blast.gd:11-17` | Rare; three firsts in the whole game |
| Island | Top centre: city-day clock and sun dial; moments one at a time (a lobe opens in 0.5 s, holds 3 to 8 s, closes 0.45 s, 6 queued at most) | `ui/island.gd:42` | No standing "next step" line |
| Wallet plate lines | "No Town Pass yet" (orange), "Free thali ready" (mint), "Your chest is ready, at your door" (gold), "owed to you: ... waiting for your Town Pass" | `ui/energy_plate.gd:127-152` | Informational; nothing says where to go |
| Bounty Board sheet | "Every quest costs energy and pays in USDC ... Payouts wait for your Town Pass. You have N energy." | `world/bounty_board.gd:163-192` | Only seen once the board is open |
| Place name | Under the minimap, rolls when you change place | `ui/game_hud.gd:400-453` | **Always reads "Tallyport"**: it reads `world.sites`, which is filled only with `--game` (`valley/world.gd:1299-1313`) |
| Link notice | "Can't reach the town's server. Trying again…" after 3 s | `ui/link_notice.gd` | Never shows for a nameless connection (fact 5) |

### 2.2 Where it is missing

- No first objective after the letter. The first hour the docs describe ("The Unload", a gold marker to the harbour crane, the Town Pass desk, the free thali, the Bounty Board, the chest) does not exist in code. The four items that do exist (Town Pass desk, free thali, Bounty Board, chest) have no ordering and no pointer.
- New players have 0 USDC (`server/rules.toml`: `start_usdc = 0`) and 100 energy. The first errand costs 10 energy and pays about 0.04 USDC with the offline seed pool (my arithmetic from `house.rs:377-384` and `rules.toml`; not run), and the pay is held until the Town Pass. Nothing explains this at the moment it happens except the line "Held for you" in the wallet plate and the island moment "Owed to you".
- The Town Pass desk sits at `(-62.6, 7.4)`, far west by the Arrival Hall (`world/tallyport.gd:23`), and the free thali counter far east (`FOOD_COUNTER_AT`, `valley/world.gd:19`); neither is marked until a quest points there.
- Paid meals need USDC in the wallet, and the wallet is empty until the Town Pass pays something. A new player cannot buy a meal on a real chain without outside funding. (On the rehearsal server the F1 panel's Fund action does it.)
- Controls other than W (Walk) are never taught. Mouse look captures the cursor in third person; Esc frees it; nothing says so.
- Mobile and touch: no touch input exists anywhere in the scripts.

---

## 3. Every quest, errand, minigame and activity

Status words: **works** (end to end, the bot covers it), **partial**, **stub**, **dead**.

All "things in town" are registered with `TownThings` (`world/town_things.gd`): `{at, reach, hint, press, over, priority}`. The key `E` ("interact") presses the nearest thing in reach that has a hint, unless a sheet, a film or a rush is up (`Tallyport._busy`, `world/tallyport.gd:95-98`). A quest step at a thing has priority 1 and goes first.

### 3.1 Bounty Board (works)

- Code: `world/bounty_board.gd` (the board, 8 pinned 3D cards, `CARDS = 8` at `:11`), `ui/board_sheet.gd` (the held-up sheet), `client/town_state.gd:97-132` (`offers`).
- Place: `BOARD_AT (-21, 0, -11.2)` in the square (`world/tallyport.gd:18`).
- Flow: E -> `open()` (`:157`) -> asks `GET /arkiv/campaigns` (cached 10 s) -> `BoardSheet` with one row per offer, Up/Down choose, Enter "Take this quest", Esc leave -> `TakeQuest{quest}` (`:194`) -> `QuestTaken` event, `replied` -> "Taken. First: ... It's on your map and in your quest log." and the sheet closes after 1.6 s (`:203-210`).
- Server fields: `city.bounty[]` (live sponsored cards, `kind:"sponsored"` only; `boosted` ones pay for the mystery), `city.errands.{list,rate,per_day,energy}`, `city.mystery`, `city.grandma`, `you.errands_left`, `you.mystery_left`, `you.grandma_done`, `you.quests`, `you.energy`, `you.human`.
- Refusals shown through `Refusals.say`: `NotEnoughEnergy`, `NoErrandsLeft`, `AlreadyOnQuest`, `CampaignClosed`, `NoSlotsLeft`, `PerHumanCap`, etc.
- Gaps: `city.errands.list` is the whole book (4 errands), not a day's pick of 3 (`server/crates/server/src/protocol.rs:591-597`), so all four show every day. One-at-a-time reading is a list, not cards. "on Arkiv" badge needs the publisher to answer. No hold-to-tear.

### 3.2 Market Rush, Kofi's stall (works, with caveats)

- Code: `market/stall.gd` (410 lines), `market/stall_shift.gd` (rules with no scene), `market/customer.gd`, `ui/order_bubble.gd`, `ui/shift_screen.gd`, island run pill (`ui/island.gd:339-356`).
- Place: `STALL_AT (-16.2, 0.31, -27.3)` inside the Market Hall (`valley/world.gd:15`).
- States: away; behind the counter (`AISLE` rect, `market/stall.gd:119-135`) with the hint "E Start a Market Rush · N of 3 left today"; `_starting` (command sent, no answer); `in_rush` (server's `RushStarted`, `:154-160`); `_quiet` (server said `RushFull`); ended by the bell (`RushTimeUp`/`RushEnded`) or by walking away (client sends `EndRush`).
- Server messages: `StartRush`, `ServeOrder` (with a ref), `EndRush`; events `RushStarted`, `OrderServed`, `RushTimeUp`, `RushEnded`; `you.in_rush`, `served`, `rush_ends_at`, `runs_left`, `best_today`, `best_run`; `city.rush.{run_ms, runs_per_day, pot, today[]}`, `city.most_orders_per_run`.
- UI: `ShiftScreen` covers the HUD plates (it sets their modulate to 0 and restores it, `ui/shift_screen.gd:333-351`): best run, served count, the order card with a patience bar, Kofi's line (from `Cast`), the basket and held item, "Hand it over" pill, combo counter. A chalkboard 3D label by the counter shows runs left, best and pot (`market/stall.gd:190-196`).
- The gameplay is entirely client-side: customers arrive every 2 to 8 s (with 18% lulls), browse 0.8 to 4.5 s, 15% just look, queue of 3, patience 35 to 70 s (`market/stall.gd:17-24`). Items are taken and swapped from three crates (apple, mango, lime). Only the final handover sends `ServeOrder`.
- Caveat: the server counts any `ServeOrder` up to 40 per 90 s (`rush.rs:39-68`) and pays the top 10 of the day from a pot (`rush.rs:135-160`). A modified client could post 40 at will.
- Gaps: no medals or run card; the post-run summary is only the island moment "Rush over." with the count and best.

### 3.3 Spice Run, the exchange swap (works; needs a live sponsor campaign)

- Code: `world/spice_run.gd`, `ui/token_amount.gd`, kiosks in `market/kiosks.gd`, template in `server/quests.toml` (`spice_run`).
- Steps: `cargo` (talk to the harbourmaster, E; the server advances 0.5 USDC if the wallet is short, which needs the Town Pass), `swap` (exchange kiosk on the landing: Uniswap quote sheet, Q for a new quote, Enter to swap), `deliver` (Spice Merchant in the Market Hall: E). Both on-chain steps show "Waiting for the chain…" until `QuestStepDone` or `QuestStepFailed`.
- Server messages: `QuoteSwap`, `Swap`, `Deliver`, `QuestStep`; events `SwapQuoted`, `QuoteFailed`, `QuestStepSent`, `QuestSwapped`, `QuestStepDone`, `QuestStepFailed`; the swap step carries `quote{usdc_in, amount_out, min_out, fee_bps, slippage_bps, symbol, decimals, quoted_at, fresh_until}` and `quote_ready_at`. Rules: quote good for 60 s, a new one at most every 15 s per player, slippage 1% (`rules.toml [templates.spice_run]`).
- UI: `BoardSheet` rows (you pay, you get about, the pool's fee, the least you will take, the quote's clock, your wallet) refreshed every 0.5 s (`world/spice_run.gd:14`). An old quote is never swapped on; the kiosk asks again first (`:171-185`).
- Gaps: it only exists while a spice_run campaign is live. The offline server seeds one (`rules.toml [[offline.campaigns]]`). The exchange and the merchant give nothing outside the quest (hints are empty). Ten other kiosks are shuttered scenery.

### 3.4 Sign painter, "Paint Your Shop Sign" (works; needs the Town Pass)

- Code: `world/sign_painter.gd`. Place: painter at `(-26, 0, -13.2)`, your sign post at `(-28.2, 0, -13.6)` (`world/tallyport.gd:21-22`).
- Steps: `painter` (talk, E), `sign` (sign: type a line up to 80 characters, `PaintSign`; the server writes it as the ENS `description` record on your name).
- Events: `SignPainting`, `RecordsSet`, `QuestStepDone`, `QuestStepFailed`. A 3D label (`_text`) shows your sign, with your ENS name under it (or "no name yet: it comes with the Town Pass").
- Refusal: `NoName` (no ENS yet), `BadSign`.
- Gaps: the "town's latest signs" wall in the docs does not exist; only your own sign shows.

### 3.5 Price Call (works)

- Code: `world/price_board.gd`. Place: `PRICE_AT (-31.5, 0, -11.2)`. Chalkboard with today's food price and three slots (up, flat, down).
- Messages: `PriceCall{call}`; events `PriceCalled`, `PriceCallSettled`; `city.price`, `city.open_price`, `city.day_ms`, `city.day_elapsed_ms`, `you.price_call`.
- Settles when the next city day opens (a city day is one real hour). A right call earns 2 tickets. The result only appears as an island moment ("Right call!" or "Not this time."); the chalkboard does not change.

### 3.6 The chest at your door (works)

- Code: `world/door_chest.gd`. Place: `CHEST_AT (-38.9, 0, 38.1)` in the Homes' courtyard, the weekly strongbox 1.05 m beside it.
- Daily chest every 24 h; tier wood, brass at a 3-day streak, gold at 7 (and one better in a week the Town Goal is reached). Weekly strongbox needs 5 of the last 7 days.
- Messages: `OpenChest{weekly?}`; event `ChestOpened{weekly, tier, contents{energy, tickets, voucher, golden_drop}}`; `you.chest{ready_at, tier, pity, pity_every, weekly_ready_at}`, `you.streak`.
- Animation: ready = pulsing glow (omni light 0.8 to 1.2) and a slightly lifted lid; on `ChestOpened` the lid swings to -1.9 rad (0.45 s, back easing), glow to 4.0, contents sheet at 0.95 s, lid closes after about 2.4 s more (`world/door_chest.gd:179-191`). The only sound is `paper`.
- Contradiction: the contents sheet looks for a `usdc` field for the weekly bonus (`world/door_chest.gd:204`), but the server puts the weekly bonus in `golden_drop` (`server/crates/rules/src/chest.rs:221-225`), so the weekly strongbox shows "A golden drop" and the "streak bonus" row never appears.
- The first chest is ready on day one only if the server says so; the letter does not mention it.

### 3.7 Common Table meals and the free thali (works)

- Code: `market/food_counter.gd`, `ui/food_menu.gd`, `ui/price_tag.gd`. Place: `FOOD_COUNTER_AT (18.65, 0, 12.38)`.
- Messages: `BuyMeal{item, voucher?}`, `FreeMeal`; events `MealOrdered`, `MealEaten`, `MealFailed`, `FreeMealEaten`, `VoucherUsed`; `you.energy`, `meal_pending`, `free_meal_at`, `vouchers`, `usdc`; `city.menu[]{name, price, max_usdc, was, energy}`.
- Flow: stand in the counter's front rect, E on a food -> menu (rows fade in over 0.5 s, 0.06 s stagger) -> Enter pays. A paid meal is async: `MealOrdered` ("Paid. Your ticket is on its way to the chain...") then `MealEaten` seconds later on Sepolia. The player holds the plate, two bites (0.35 s, 0.8 s), gone at 1.1 s (`market/food_counter.gd:116-129`).
- Price tags: a split-flap over each dish (0.4 s flip, arrow nudge) within 3 m (`ui/price_tag.gd:98-157`).
- Gaps: no cook. `FoodMenu` shows "Mei" and says "Asking Mei for the thali…" (`ui/food_menu.gd`), and quotes `Cast.line("mei")`, but Mei exists only as a named person with `--game`. The kicker reads "Mei · Tally Square" though the table is nowhere near the square. The menu header looks up `MapData.SITES` from the old quarter (`ui/food_menu.gd:69`).

### 3.8 Town Pass and World ID (partial)

- Code: `world/town_pass_desk.gd` (clerk at the Arrival Hall; desk), `ui/phone_wallet.gd` (button "Get my Town Pass"), server `hub.rs:401-415`, HTTP verify page in `server/crates/server/src/http.rs`.
- Flow: `TownPass` -> `result{url}` (one-time, good for 15 minutes) -> `OS.shell_open(url)` -> the player proves personhood in the browser (World ID, or a rehearsal button on a `--debug` server) -> the game waits for `HumanVerified`, then everything owed is paid and `NameRegistered` writes `name.tallyport.eth`.
- UI: the clerk's hint "Get your Town Pass" / "Waiting for World ID…", wallet plate line, island moments ("Town Pass stamped.", "Your name."), full blast for `first town_pass`.
- Gaps: no in-game World ID window; a browser tab does the work. On the web build I infer `window.open` outside a click may be blocked (not checked). The Town Pass is also a campaign template with its own quest steps (`clerk`, `verify`).

### 3.9 Bank clerk (stub)

`TownNpc` "Arthur, the bank's clerk" at `(-22.88, 0.76, 18.1)` (`world/tallyport.gd:24, 80-84`). He breathes, turns his head, waves. The only use is Grandma's page two ("ask the bank clerk", place `bank`). The bank counter and the Homes room are scenery (`valley/world.gd` `_furniture()`, "nothing to do at them now"). Nothing banking exists.

### 3.10 Rescue meal (works)

Server: with the Town Pass, energy under 10, less USDC than the cheapest meal and the free thali already eaten, `RescueComing{at}` then `RescueMeal{energy, direct}` (2 minute delay, once a day). Client: `Tallyport._rescue` (`world/tallyport.gd:176-205`) sends a `Visitor` who walks up (2 m/s from 11 m), says two lines, and hands over a steel plate (`avatar.hold` flies it to the player's hand). Island moments "Help's coming." and "A thali, on the town." The bot's `--rescue` mode covers it.

### 3.11 Errands (works, shallow)

Four errands (`quests.toml`): The Chai Round, The Lost Ledger, Chalk the Price Board, Letters from the Ferry. Each is two steps (visit or talk at a `place`), done by pressing E at a gold-diamond place (`world/quest_marks.gd:103-124`). 10 energy each, 3 a day. No props: nothing at the "day book on the bench" or "the baker". Pay is `errand_rate` (15% of the fixed bucket's day budget divided by 15, `server/crates/rules/src/house.rs:377-384`).

### 3.12 Daily mystery (partial)

Two mysteries (Missing Scale, Night Bell), three plain steps each, 50 energy for 0.5 USDC (or a sponsor's payout if boosted). No evidence, notebook, or props; the steps are "visit" and "talk" at places. It shows as a Bounty Board card.

### 3.13 Grandma's Ledger (works)

Once a season, 50 energy, `any_order` steps: page one (paper at the square, only on a day the market has news, else `NotAShockDay`), page two (bank clerk), page three (eat three meals you pay for), then the strongbox at your door. Client: torn-page meshes lie on the ground at the step's place (`world/quest_marks.gd:51-70`), a steel strongbox at your door grows a fan of pages as they are found (`:173-221`), and on `QuestDone` a full-screen reveal "Her strongbox is open" (`world/tallyport.gd:166-172`). Reward: up to 1 USDC, 5 extra tickets, title "Grandma's Heir", stamp `grandmas-ledger`.
Contradictions: `quests.toml` says the pages are "around Mumbai's old market", the game is Tallyport; the letter hints at pages but nothing points the player at the quest.

### 3.14 Hold the Line (partial)

Server complete (3 days, random on-chain checks, `server/crates/rules/src/quests.rs:956-1050`). Client: no marker (chain step), the phone Quests page prints "Held through N checks..." (`ui/phone_quests.gd:49-53`). No world prop. The F1 panel can open such a campaign.

### 3.15 The rest

- **Weekly draw and Town Goal:** shown only on the phone Town page (`ui/phone_town.gd`) and as island moments (`TownGoalReached`, `DrawCommitted`, `DrawWon`; `DrawRevealed` has no handler). No drum, no lanterns in the world.
- **Feed and reactions:** phone Feed page, `React{post, emote}` once per post (`ui/phone_feed.gd`).
- **Referral:** phone Town page, `Refer{player}`.
- **The Tally paper:** `PaperPublished` shows a folded corner with the headline for 14 s; N opens the front page (`ui/morning_paper.gd`).
- **Season change:** `SeasonChanged` (once a real week) -> ferry arrives cinematic, banners, trees change (`world/moments.gd:92-108`).
- **Not wired in the client at all:** `Follow`, `Unfollow`, `CarveFirst` (no UI sends them), other players' profiles (only your own is asked, `ui/phone_profile.gd`).
- **Decoration only:** `TownPeople` (about 19 sitters/standers, 3 fishers, 10 walkers on fixed routes, `life/town_people.gd:15-37`), the 16 kiosks (2 staffed, 10 shuttered, 4 "always open" with names like "Meena's Fruit", `market/kiosks.gd`), residents from the server (about 20, drawn by `OtherPlayer` walking `WAYS` between five places, `life/other_player.gd:19-32`).

---

## 4. Every UI element

All UI hangs under one `CanvasLayer > Control` called `ui` built at the start of `_market()` (`valley/world.gd:1361-1370`). The canvas is 1280 by 720 with `canvas_items` stretch and `expand` aspect (`game/project.godot`). HUD plates fade through `modulate` (opening) or are hidden by `ShiftScreen`.

Z-order, from the code: title 30, settings 35, cinema 40 (`ui/cinema.gd:10`), paper sheets 50 (`ui/paper_sheet.gd:14`), milestone blast 100, `BootIntro` on its own `CanvasLayer` 100.

| Element | File | Shows, and from which fields | Motion (code) | Used? |
|---|---|---|---|---|
| Boot logo | `ui/boot_intro.gd` | coin mark, name | line 0.25 s, pop 0.5 s with back ease, word open 0.6 s, breath, wipe 1.7 s quart, ring 1.1 s expo, flash | yes, once per launch |
| Title | `ui/title_screen.gd`, `ui/menu_word.gd` | menu; live plate: `city.price`, `city.day`, presence count, price sparkline (last 40 prices), news line from `city.paper.headline` and `FeedPost` | name fade 1.1 s, words 0.6 s staggered, news scrolls 46 px/s, camera drift over 60 s, film bars | yes |
| Cinema | `ui/cinema.gd` | letterbox bars (0.11 of height), title card, mark wipe, subtitles (`say`) | bars 0.5 s cubic, wipe 0.9 s quart, card fade 0.35 s, subtitle 3.5 s | yes |
| Ferry ticket | `ui/ferry_ticket.gd` | name field, refusals | open 0.18 s | yes |
| Gran's letter | `ui/gran_letter.gd`, `ui/strings.gd` | text | open 0.18 s | yes |
| You plate | `ui/energy_plate.gd:56-78`, `ui/player_face.gd`, `ui/energy_pips.gd` | `you.name`, `energy`, `energy_max`, `energy_regen_at`, `free_meal_at`, `meal_pending` | pips fill 0.32 s each, 0.07 s stagger; last pip breathes 1.6 s; text refreshed every 0.5 s with no animation | yes. The face is a fixed PNG (`assets/ui/player_face.png`), not the player |
| Wallet plate | `ui/energy_plate.gd:81-152` | `you.usdc`, `human`, `tickets`, `streak`, `chest`, `pending`, `pending_rewards`, `rescue_at`, `city.chain` ("REHEARSAL" when offline) | none (no counter roll) | yes |
| Island | `ui/island.gd` (808 lines), `shaders/ui/island.gdshader` | city day clock and sun dial (`city.day_ms`, `day_elapsed_ms`, `world.look.to_sun`), run pill, moments from roughly 35 event types, a glance card (energy, best run, day) on hover or Alt | open 0.5 s, hold 3 to 8 s, close 0.45 s, 0.6 s between; one shader draws every shape | yes; hidden during title, opening, films, blast, sheets (`_hidden`, `:302-306`) |
| Minimap | `ui/minimap.gd` | map image painted once from `world.data` plus building footprints; player arrow; gold goal | redrawn every frame; ping ring 2 s | yes. The paint loops 800 by 740 pixels in GDScript at boot (`:82-122`, from `bounds` in `world/valley/world.json`) |
| Place name | `ui/game_hud.gd:400-453` | nearest `world.sites` name | roll 0.4 s | broken: always "Tallyport" (sites empty) |
| Pocket bar | `ui/game_hud.gd:153-293` | five launcher icons, key numbers | lift 0.52 s, ring draw 0.64 s, squash 0.04 + 0.08 s | yes; not an item bar |
| Key list | `ui/game_hud.gd:296-329` | Run, Rotate, View from the real bindings | none | yes, 3 lines |
| Ticker | `ui/game_hud.gd:122-151` | `FeedPost` lines | none | dead: hidden by `Island` (`ui/island.gd:166`) |
| Toast | `ui/game_hud.gd:331-393` | season shocks | none | dead: `toast()` forwards to the island, the plate is never shown (`:378-379`) |
| Key hint / name tag | `ui/key_hint.gd`, `ui/world_tag.gd` | key + words; as a tag with no key it is a dark remark plate | pop 0.22 s back ease, tail drop 0.12 s later, cap sinks 0.05/0.08/0.1 s | yes; name tags on other players show within 7 m of the camera (`life/other_player.gd:TAG_WITHIN`), NPC names within 9 m. Hidden past 12 m (`world_tag.gd:FAR`) |
| Price tag | `ui/price_tag.gd` | `city.menu[].price`, `was` | split-flap 0.4 s, arrow nudge 0.12 + 0.18 s | yes |
| Order bubble | `ui/order_bubble.gd` | a customer's item icon | pop 0.16 s | yes |
| Shift screen | `ui/shift_screen.gd` | rush run | pop 0.9 s for the packed label | yes |
| Board sheet | `ui/board_sheet.gd`, `ui/paper_sheet.gd` | list of rows `{title, sub, figure, badge}` with keys Up/Down/Enter/Esc | open 0.18 s | yes: board, exchange, price call, sign, chest |
| Food menu | `ui/food_menu.gd` | `city.menu`, `you.usdc`, `you.energy`, `vouchers` | rows fade 0.5 s | yes |
| Phone | `ui/phone.gd` + `phone_feed`, `phone_quests`, `phone_wallet`, `phone_town`, `phone_profile` | feed, quests, wallet, town, me | slide up 0.18 s | yes; Tab, 1 to 5, Esc |
| Mentor chat | `ui/mentor_chat.gd` | `MentorSays` line; typed answers | types out at 45 characters/s; rows slide in 0.4 s | yes; H |
| Morning paper | `ui/morning_paper.gd` | `city.paper` | open 0.18 s; corner 14 s | yes; N |
| Milestone blast | `ui/milestone_blast.gd`, `ui/first_note.gd` | `FirstEarned`, Grandma reveal | 4.5 s, rays, rings, confetti (40) | yes |
| Link notice | `ui/link_notice.gd` | connection state | none | yes, except for nameless connections |
| Settings | `ui/settings_panel.gd` | Picture, Sound, Controls (rebind), Game | open 0.6 s | yes; Esc |
| Test panel | `ui/test_panel.gd` | rehearsal actions | none | F1, rehearsal server only |
| Refusals | `ui/refusals.gd` | about 60 refusal sentences from the server's refusal fields | none | yes |
| World labels | `Label3D` in `bounty_board.gd`, `price_board.gd`, `door_chest.gd`, `sign_painter.gd`, `stall.gd`, `kiosks.gd` | the boards' words | none | yes |

Server fields the client never reads: `you.best_board`, `you.following`, `city.food_index_bps`, `city.treasury`, `city.float`, `city.resident_walk_ms`. `house` is read in a single place.

Phone behaviour worth knowing: every `you`, `city` or `synced` message while it is open calls `refresh()`, which clears and rebuilds the whole page (`ui/phone.gd:88-90`, `ui/phone_page.gd:15-18`). The server sends `you` on every change to you, `city` to everyone on every public event, and `you` for each energy point (`server/crates/server/src/hub.rs:762-840`).

---

## 5. Animation and feel

### 5.1 Character

- **Controller:** `valley/player.gd`. `CharacterBody3D`, capsule 0.35 m by 1.6 m, walk 3.4 m/s, sprint 1.65 times (Shift), acceleration `1 - exp(-9 dt)`, gravity 22, kerb and stair step-up to 0.5 m (`:82-97`). Input is `Input.get_vector` on W/A/S/D or arrows, rotated by the camera yaw. No jump, no dodge.
- **Drawn body:** `physics_interpolation` is on project-wide (`game/project.godot [physics]`). The body is placed every frame at the interpolated position (`player.gd:117-123`) and turned with `lerp_angle(..., 1 - exp(-12 dt))`. The head looks where the camera looks within the neck's reach.
- **Animation:** `valley/hero.gd` plays clips Idle, Walk, Run by hand (`_ap.advance(delta)`), then layers a procedural gait on the skeleton (`valley/gait.gd`, 364 lines): planted feet, pelvis spring (stepped at 1/120 s), feet stepped at 1/45 s at most, lean into speed, arms swing, hem and hair trail on a spring. Arms are posed for carrying (`CARRY_*`), reaching (0.14 s out, 0.2 s back) and a bite. One-shot gestures: `wave()` plays the `Victory` clip, `gesture("Interact")` for handovers. There is no AnimationTree and no state machine. Player emotes, jump, sit and a "hold E" animation do not exist.
- **Scooter:** `set_on_scooter` has no callers anywhere; `on_scooter` is only read by `Presence` and by `OtherPlayer` for remote riders (`valley/player.gd:126`, `life/other_player.gd`). Dead for the local player.
- **People:** `life/person.gd` (393 lines) is the body for every NPC, with the same clip approach.
- **Others:** `Presence` sends position every 0.2 s (every 2 s while still, `client/presence.gd:24-33`); `OtherPlayer` draws a player 0.25 s behind the newest point and lerps between points (`life/other_player.gd:150-165`).

### 5.2 Camera

`valley/camera_rig.gd` (369 lines). Three views cycled with C: top (7 to 30 m, fov 38), third (2.2 to 9 m, fov 62, default; saved view and distance per mode), first (fov 72, head bob). Third-person follow:

- A critically damped spring on the orbit point, 0.1 s across and 0.22 s up (`:233-246`); in the top view 0.3 and 0.45 s.
- Sideways travel swings it round; walking on brings it behind; slope-aware pitch; sprint widens fov by 7 and pulls back 12% (`VIEWS`, `:25-32`).
- Collision: a 0.2 m sphere sweep pulls in at once and eases out at `1 - exp(-5 dt)`; in the top view it tilts over buildings.
- Idle drift after 40 s of no input (`cinematic_on` setting).
- Mouse look captures the cursor in third and first person (`:289-294`); Esc frees it.
- `hold_view(yaw, pitch, side)` eases the view to a fixed heading while working at the stall, the food counter and the harbourmaster (`:349-353`). `focus_on` and `release` (interior glide) are never called in the valley build.

### 5.3 Cutscene and cinema

- **Director** (`world/director.gd`): one extra `Camera3D` with physics interpolation off. `fly(eyes, ats, seconds, fov, skippable)` follows a Catmull-Rom path with a smootherstep ease (`:17-18, 20-27`); `follow(callable, seconds)` for moving subjects (the ferry); `land(seconds)` blends from the last shot into the player's camera transform and fov; `cut()`. Any key or mouse button skips a skippable shot (`:94-100`). The coroutines advance on `process_frame` using `get_process_delta_time`.
- **Cinema** (`ui/cinema.gd`): bars, cards, the mark wipe (`shaders/ui/mark_wipe.gdshader`), subtitles. Every call returns on completion so scenes read top to bottom with `await`.
- **Opening** (`world/opening.gd`): the ferry is animated procedurally (a Catmull-Rom route, 22 s, speed eased `1 - (1 - u)^1.7`, bob 0.03 m); the player is carried with the deck. No Blender-authored film.
- **Moments** (`world/moments.gd`): only two kinds remain, the first-time look into each of five places (2.6 s flight, bars off, keys pass through) and the weekly season ferry (5 s). The docs' other moments are not built.
- **Settings** eases the camera aside 0.7 m with `h_offset` over 0.9 s (`ui/settings_panel.gd:158`).

### 5.4 Feel, from reading the code

Smooth:
- Physics interpolation plus camera spring plus interpolated body draw; the camera sets itself to the interpolated position (`camera_rig.gd:144-145`).
- Cutscene motion is eased (smootherstep) and uses the ferry's interpolated transform (`world/opening.gd:139-140`).
- UI tweens are short with cubic or quart easing.
- Other players are buffered 0.25 s.

Janky or risky:
1. **Frame pacing is decided once.** `_pace` measures the average frame rate 4 to 9 s after the world is built, and if it is under 92% of the screen's rate, caps the game at half the refresh for the whole session (`valley/world.gd:1569-1583`, `:72-74`). That window lands on the logo, the burst wipe and the ferry film, not on play. The setting can turn it off.
2. **Boot freeze.** The world and the minimap paint (592,000 pixels with per-pixel lookups) run on the main thread before the logo.
3. **Rebuilt UI.** Phone pages rebuild on every server message; `BoardSheet._draw_rows` frees and recreates all rows on every refresh (every 0.5 s while the exchange is open); `PaperSheet._process` calls `reset_size()` every frame it is visible and each sheet has a full-viewport `BackBufferCopy` plus a blur shader (`ui/paper_sheet.gd:23-28, 86-88`).
4. **Interpolation mixing (not verified).** Bodies, cameras and the Director are set to interpolation off. The harbourmaster, visitors, quest diamonds and customers move in `_process` on nodes that inherit interpolation on (`world/harbourmaster.gd:33-52`, `world/quest_marks.gd:126-135`). Godot expects `_process` movement on interpolated nodes to judder; worth checking in play.
5. **The ferry ride runs on physics ticks** (`world/opening.gd:151-157`) while the title camera is placed in `_process` from the ferry's interpolated transform; fine, but the ride clock starts before the first visible frame.
6. **Money and prizes do not move.** The wallet number changes at the next 0.5 s tick with no roll or flight. The only "item flies" code is `hero.hold` (from a world point to the hand, `valley/hero.gd:115-119`) and the stall's item tween (0.22 s).
7. **Sound** is thin: files exist for bell, coin, door, ferry horn, paper, stamp (unused), steps, five ambiences, three music beds. The coin plays only for `OrderServed` and `MealEaten` (`world/sound.gd:16, 99-101`). Quest done, reward paid, chest contents and the Town Pass stamp are silent (chest uses `paper`).

---

## 6. Server side

### 6.1 Messages (protocol version 3, `server/crates/server/src/protocol.rs`)

Client to server:
- `hello{protocol, player?, secret}` (no `player` = nameless), `move{x,y,z,yaw,anim}` (not saved, no reply), `profile{name}`, `command{ref, command}`, `debug{action}` (rehearsal only).
- 22 commands (`:57-121`): `ClaimName`, `TownPass` (both answered by the hub, not the rules), `StartRush`, `ServeOrder`, `EndRush`, `FreeMeal`, `BuyMeal`, `OpenChest`, `TakeQuest`, `QuestStep`, `AbandonQuest`, `Swap`, `Deliver`, `QuoteSwap`, `PaintSign`, `PriceCall`, `Refer`, `CarveFirst`, `AskMentor`, `React`, `Follow`, `Unfollow`. The game sends 19 of them (not `CarveFirst`, `Follow`, `Unfollow`).
- Debug actions (`:177-204`): `Skip`, `NextSeason`, `Fund`, `FundBucket`, `ReadyChest`, `PassTown`, `NewCampaign`.

Server to client: `snapshot{seq, debug, you, city, feed}`, `event{seq, event}`, `you`, `city`, `time`, `profile`, `result{ref, ok, refusal?, url?}`, `debug_done`, `nameless`, `hello_refused`, `presence{players[]}`, `left`, `kicked`, `error`.

Rules the client can rely on (`hub.rs:762-840`):
- Events come **before** the `you` they changed; the client reads quest text from the old `you` for that moment (`ui/island.gd:246-251`).
- A public event (about the whole city) sends a fresh `city` to everyone; private events that change the city also do (`protocol.rs:217-232`).
- Energy regeneration sends `you` with no event.
- A `hello` for a taken name with a wrong secret is `NameTaken`. 60 name tries a minute and 10 new names an hour per address, else `SlowDown`.
- Commands are idempotent by `ref` (`RefUsed` is treated as success by the client, `client/town_client.gd:262-272`).

### 6.2 `you` (`protocol.rs:376-444`)

`name, title, energy, energy_max, energy_regen_at, in_rush, served, rush_ends_at, runs_left, best_run, best_today, firsts[], following[], ranks, best_board, neighbours, wallet, usdc, human, ens, sign, quests[], errands_left, mystery_left, grandma_done, chest{ready_at, tier, pity, pity_every, weekly_ready_at}, streak{days, week_days, need}, tickets, vouchers, pending, pending_rewards[], meal_pending, free_meal_at, rescue_at, price_call, titles[], stamps[], referrer`. Each quest: `{quest, title, story, kind, campaign, energy, any_order, steps[{id, kind, text, place, done, waiting, quote?, quote_ready_at}], hold}`. `usdc` and `wallet` are `null` until the chain makes the wallet.

### 6.3 `city` (`protocol.rs:572-675`)

`day, day_ms, day_elapsed_ms, now_ms, real_day, real_day_ms, next_real_day_at, chain, price, open_price, food_index_bps, menu[], food{}, free_meal_energy, rush{run_ms, runs_per_day, most_orders, pot, today[]}, most_orders_per_run, errands{rate, per_day, energy, list[]}, mystery, grandma, golden_drop, bounty[], house, treasury, float, town_goal, draw, shock, paper, resident_walk_ms, emotes, boards, season`.

### 6.4 The numbers (`server/rules.toml`, `quests.toml`)

- Energy: max 100, new players start full, +1 every 4 min only below 40. Meals: chai +10, vada pav +32, thali +70; free thali +40 once per 24 h. Meal price is FOOD at the live pool price (base 0.004 USDC per FOOD; chai 1 FOOD, vada pav 3, thali 6).
- Quests: errand 10 energy, 3 a day; mystery 50 energy, 0.5 USDC, 1 a day; Grandma 50 energy, 1 USDC, 5 tickets, once a season; sponsored: the card's energy and payout. Every finished quest earns 1 ticket.
- Rush: 90 s, 3 runs a day, at most 40 orders, 1 ticket per run with an order, top 10 share the day's pot.
- Chest: wood/brass/gold gives energy 10/20/30, tickets 1/2/3, meal voucher chance 10/25/50%, golden drop (0.05 USDC) chance 5/10/20%; every 10th chest without a drop has one. Weekly: 0.25 USDC, 3 tickets, 30 energy, needs 5 of 7 days.
- Town Pass: required for any payout, for vouchers, and for the cargo advance (`meals.rs:126`, `quests.rs:418`). Unpaid rewards are held (`Waiting::TownPass`) and paid when the pass lands.
- Clock: a city day is 1 real hour, a real day 24 h, a season 168 city days (one real week) with a shock (harvest, festival, drought).
- Rescue: under 10 energy, 2 minute delay, once a day.
- The rules emit a `QuestDone{reward{usdc,tickets,title,stamp}}`; there is no loot, rarity or box in the rules.

### 6.5 Trust and gaps

- **Wallets are server-side.** A new player gets a wallet from the chain after `ClaimName` (`hub.rs:526-565`); `town_pass_check` needs `player.wallet` (`server/crates/rules/src/human.rs:160-166`). So World ID cannot come before an account exists.
- Location is not verified: `QuestStep` for talk, visit, paper, strongbox and cargo is accepted anywhere, only order is checked (`quests.rs:378-398`).
- `ServeOrder` is not tied to customers (`rush.rs:39-68`).
- The offline server's "town" is a rehearsal (`city.chain == "offline"`); the client labels it REHEARSAL.
- `errands.list` returns all errands (see 3.1).

---

## 7. Dead, duplicated or contradicting code

| What | Where | State |
|---|---|---|
| Old Quarter world | `world/world.gd` (2092 lines) | Dead: `--world=quarter` needs `world/quarter/world.json` (missing; `ls game/world/quarter` shows buildings.json, models, shaders, textures) |
| Old player, avatar, camera | `player/player.gd`, `player/avatar.gd` (0 references), `player/camera_rig.gd` | Used only by the quarter world; duplicated by `valley/player.gd`, `valley/hero.gd`, `valley/camera_rig.gd` |
| Quarter-era systems | `life/life_director.gd`, `life/villager.gd` (0 outside), `life/ambient.gd`, `world/site.gd`, `world/weather.gd`, `world/tree_builder.gd`, `world/grass_builder.gd`, `world/ground_cover.gd` (0), `world/orig_trees.gd`, `world/map_data.gd` | Quarter only; the valley build ignores them. Still covered by `scenes/tests/*` and `tests/` |
| Duplicated builders | `valley/grass_builder.gd` vs `world/grass_builder.gd`; `valley/trees.gd` vs `world/tree_builder.gd`; `valley/vh_impostor.gd` (class `ValleyImpostor`, 0 references) vs `vh/vh_impostor.gd` | |
| `vh/` reference scene | `vh/vh_ref_scene.gd`, `scenes/vh_ref.tscn` | Dev tool |
| `--game` layer | `valley/world.gd:1299-1357` (`_doors`, `_cast`), `world/spot.gd` | Adds door spots and named people (`POSTS`, `OUTFITS`). Nothing consumes `player.site` (`valley/player.gd:152-156`); only the minimap footprint and the place name read `world.sites` |
| Named cast | `life/cast.gd` (11 people with lines) | Mostly unused. `FoodMenu` and `ShiftScreen` borrow Mei's and Kofi's lines. Priya, Bo, Ingrid, Elias, Dario, Yusuf, Sam have no home in the valley build |
| Life-sim leftovers | `ui/strings.gd:7-24` (SIGNS, "To Let", "Town Project", "Workshop Soon"), `life/cast.gd` lines about workshops and pawn shops, `paper_sheet.gd` comments about loans | Words from the earlier life sim; unused or misleading |
| Old coin economy | none in logic | Gone from code. Remaining mentions are the brand's "coin" mark and an item called `Coin` hidden in the stall model (`market/stall.gd:79`). USDC only |
| Scooter | `valley/player.gd:126-135`, `valley/player.gd` consts | Dead locally, alive for remote riders in `OtherPlayer` |
| Hidden HUD pieces | `GameHud` ticker and toast (`ui/game_hud.gd:122-151, 331-393`), `MentorChat._corner` | Built, then hidden and forwarded to the island |
| Interior glide | `valley/camera_rig.gd:355-369` (`focus_on`, `release`) | Never called |
| Port dressing | `valley/port_dressing.gd` (447 lines) behind `PORT_DRESSING = false` | Kept on file by the founder's choice |
| `TestPanel` | `ui/test_panel.gd` | F1, rehearsal only; fine |
| `FoodMenu` and the old map | `ui/food_menu.gd:69` reads `MapData.SITES` | Old data feeding a live screen; "Tally Square" is wrong for the table |
| Unused sound | `assets/audio/stamp.wav` | Never played |
| Unhandled server pieces | events `BalanceChanged`, `BountyPosted`, `BountyClosed`, `LedgerUpdated`, `DayOpened`, `FoodBought`, `FoodSold`, `CityEventStarted`, `DrawRevealed`, `FirstCarved`, `Followed`, `Unfollowed` | Sent; no client handler |
| Weekly chest field | `world/door_chest.gd:204` vs server `golden_drop` | Mismatch (3.6) |
| Story names | `quests.toml` grandma story "Mumbai's old market" vs game "Tallyport" | Mismatch |
| Docs vs code | `Game_Layer_Design.md` (gate with a Tickets sign, ticket in hand, key in the letter, The Unload, hold-E, medals, passport, receipts, pantry, drum, wall) | None of these exist in code |

---

## 8. Where the planned screens plug in

### 8.1 World sign-in at the gangway gate

- Today: no gate. The ticket opens from a bounding box when the player walks 1.1 m forward on the deck (`world/opening.gd:188-193`, `ON_DECK x = 2.4`, `AT_RAIL_BOW = 3.5`). The ticket is a paper sheet over the screen, not an object in the shot (`ui/ferry_ticket.gd`). The client sends `hello{secret}` then `ClaimName` (`client/town_client.gd:155-158`, `ui/ferry_ticket.gd:109-111`).
- Plug in: replace `_open_ticket()` with a gate object (a `TownThings` entry registered by `Opening.setup`) and a new sheet before the ticket. `Opening.step` already has the states `film, deck, ticket, ashore, handing, letter`; add a `gate` state.
- Missing: server and protocol. `town_pass_check` needs an existing player and wallet (`human.rs:160-166`), so "sign in with World" must either create the account and wallet first or be a new `hello` variant that carries a proof and maps it to a name and a secret. Nothing in the client or the server does that today. A new device cannot recover an account at all (secret is local). Also needs a path for the "Continue" word on a new device.

### 8.2 Full-screen quest board

- Today: `BountyBoard.open()` (`world/bounty_board.gd:157`) fills a `BoardSheet` (paper sheet 820 px, rows, Up/Down/Enter/Esc, `ui/board_sheet.gd`). The 3D board pins at most 8 cards.
- Plug in: replace the sheet with a new full-screen `Control` registered like the sheets: add it to `any_sheet_open()` (`valley/world.gd:1565-1567`), set `player.frozen`, call `rig.take_cursor_back()` on close (`BoardSheet.close` pattern, `ui/board_sheet.gd:107-114`). Data is ready: `TownState.offers(you, city)` gives `{quest, title, story, by, energy, pays, card, on}`; `TakeQuest` and its refusals are handled in `bounty_board.gd:194-213`.
- Missing: card art, detail view, "places left" and "ends" are already text in `_fill_sheet` (`:163-192`). Today's errands are all four every day (server).

### 8.3 Quest tracking (one gold marker in the world, a minimap route, an island "next" line)

- Today: every open step with a known place gets a diamond (`quest_marks.gd:30-48`); the minimap goal is the first quest with a place (`:222-235`) and does not follow a moving person; the phone shows "Next: ..." (`ui/phone_quests.gd:53-57`); the island has nothing standing.
- Plug in: a client-side "tracked quest" id (saved with `world._save_setting`). Filter `QuestMarks._rebuild` and `_goal` by it. The island rest pill is built in `Island._build_rest` (`ui/island.gd:654`); a next-step line would sit there, or be a new kind in `Island.KINDS`.
- Missing: a tracking choice UI (phone page or board); a route. There is no navigation data anywhere (no `NavigationRegion`, no `AStar`); the paving field (`WorldData.pave_dist`, `world/world_data.gd:64`) is the only walkable hint, so a route needs a graph or a baked path. Quest places are named constants (`world/tallyport.gd:9-24`) and persons move (`place_at`, `:116`).

### 8.4 Minimap redesign

- Today: `ui/minimap.gd` (167 lines): round plate, 90 m view (`VIEW`), north up, fixed 153 px, shader samples a map image painted once at boot, N badge, player arrow, one gold goal with pings. Shown top right; the place name under it; the phone's frame keeps clear of it (`ui/phone.gd:13-15`).
- Plug in: the file is self-contained; `GameHud._build_map` instantiates it (`ui/game_hud.gd:381-393`) and `GameHud.set_goal` feeds it. A bigger map or a toggle would add inputs here.
- Missing: markers other than the goal; legend; a town-map texture at higher resolution (the current image is 1 px per metre, magnified 1.7 times with bilinear). Place labels (the name roller reads `world.sites`, empty).

### 8.5 Full town map (M)

- Today: nothing. M is unbound (`game/project.godot`; no `KEY_M` in scripts).
- Plug in: add an input action and a sheet like the others; reuse `Minimap._paint()` image (`ui/minimap.gd:82-123`) and `Tallyport.PLACES` plus `PEOPLE` for pins. Add it to `any_sheet_open()`.
- Missing: place names and icons (the building names live in `assets/town/manifest.json` and `world/valley/world.json` sites; the valley build has no label table); the "camera hold" while open.

### 8.6 Run card, job slip, receipt

- Today: the end of a rush is only the island moment "Rush over." (`ui/island.gd:180-182`); a quest finish is the island moment "Quest done!"; money is `RewardPaid` and `MealEaten`, which feed `client.payments` (last 12, session only, `client/town_client.gd:251-260`) and the phone Wallet "Recent" list with an explorer link (`ui/phone_wallet.gd:41-49`).
- Plug in: the paper look exists (`PaperSheet`, `ui/paper_sheet.gd`, with a tilt and a brand stripe `card()`); `BoardSheet` is the ready container. Events to hook: `RushEnded`, `QuestDone`, `RewardPaid`, `RewardPending`, `MealEaten` (`client.event`).
- Missing: server history (the client keeps only this session's payments; there is no "receipts" endpoint), run medal data (the server gives only counts), any print-out animation.

### 8.7 Lootbox after a quest (hold E, rarity, prize flies to the wallet)

- Today: no server concept of loot. `QuestDone.reward` is `{usdc, tickets, title, stamp}`. The nearest thing is `ChestOpened{tier, contents}` which is opened with a plain E press (`world/door_chest.gd:168-172`).
- Plug in (client): `TownThings` presses on `is_action_pressed("interact")` only (`world/town_things.gd:53-58`); hold-to-confirm needs a new "hold" option on a thing and a held-key timer. `PaperSheet.Pill.fill` is a built, unused property for exactly this (`ui/paper_sheet.gd:163-165`). The chest's lid choreography (`door_chest.gd:179-191`) is the template. The wallet plate's USDC label (`ui/energy_plate.gd`, `_usdc`) is where a prize would fly to (use its global rect).
- Missing (server): a loot drop event or a reward field with a rarity, the rules and odds, and a place to keep an unopened box. Rarity words today are only the chest tiers (`wood`, `brass`, `gold`) with colours in `door_chest.gd:8`. Missing (client): a fly-to-wallet tween, sounds (only `paper` exists), a reveal sheet.

### 8.8 Wallet and bank page on the phone

- Today: `ui/phone_wallet.gd` shows address (with explorer link), USDC, ENS name, sign, vouchers, the Town Pass state and button, owed rewards with reasons, "Recent" (this session). Read-only.
- Plug in: add a page in `Phone._pages` and `PAGES` (`ui/phone.gd:25-27`) and a slot in `GameHud.SLOTS` (`ui/game_hud.gd:19`, keys 1 to 5 currently; a sixth needs `KEY_1 + SLOTS.size()` to still fit). Commands to add must exist in the server: none for deposit, withdraw, send, or savings.
- Missing: any money-moving command, history from the server, balance over time. "Bank" in the town is scenery (3.9).

### 8.9 The HUD

| Piece | File | Notes for the redesign |
|---|---|---|
| You plate | `ui/energy_plate.gd:56-78`, `player_face.gd`, `energy_pips.gd` | face is a static PNG; pips fixed at 5 (`PIPS`); text refreshed every 0.5 s |
| Wallet plate | `ui/energy_plate.gd:81-152` | in the same `VBoxContainer` as the you plate; no counter animation |
| Island | `ui/island.gd` | one shader draws the shapes; the event-to-moment table is `_on_event` (`:174-241`); queue priority in `KINDS` (`:42`) |
| Minimap | `ui/minimap.gd` | section 8.4 |
| Pocket bar | `ui/game_hud.gd:153-293` | currently five launchers (wallet, quests, feed, town, mentor), not items |
| Key hints | `ui/key_hint.gd`, `world/town_things.gd` | one shared `KeyHint` for all things, plus separate ones in the stall, food counter and opening; fade rule 4 showings per verb |
| Name tags | `life/other_player.gd` (a `KeyHint` with no key), `world/town_npc.gd` | dark plate, not magenta; the player's own name has no tag |
| Key list | `ui/game_hud.gd:296-329` | 3 lines; generated from real bindings |
| Phone and mentor | `ui/phone.gd`, `ui/mentor_chat.gd` | Tab and H; the phone refreshes whole pages |
| Hide logic | `ui/island.gd:302-306`, `ui/shift_screen.gd:333-351`, `world/opening.gd:127` | three different ways of hiding the HUD: the island hides by visibility; the shift screen sets plates' modulate to 0; the opening sets plate modulate to 0 and tweens it back. A redesign should centralise this |

The HUD parts are created in `_market()` in this order: energy plate, link notice, stall, food counter, ..., morning paper, blast, phone, mentor, `GameHud`, island, settings, title, cinema, moments, tallyport (`valley/world.gd:1361-1500`). Adding a new top-level screen means: create it there, add it to `any_sheet_open()` (`:1565`) so the island, `TownThings`, `Moments` and the camera cursor treat it as a held-up sheet, and decide how it hides the plates.
