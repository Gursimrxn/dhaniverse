# Game layer, batch 1: report

What was built, in the order asked. Paths are relative to `game/scripts/` unless they start with `game/`, `apps/` or `docs/`.

## 1. The Bounty Board, bigger and moved

- `world/bounty_board.gd` (rewritten; the old one is backed up in the session scratchpad). The cork is 6.4 x 2.7 m (was 3.4 x 1.9), 12 cards in two rows of six, a dark head plank with "BOUNTY BOARD", a small slate gable roof, a ledge, and two iron lantern arms with warm emissive glass and a 5.5 m warm `OmniLight3D` each (no shadows).
- `world/tallyport.gd`: `BOARD_AT` is now `(-84, 0, -13.6)`. Picked from the paving field (`game/world/valley/paved.bin.gz`) and the sites in `world.json`: the road up from the landing runs north along x = -84 from the z = 28 road and meets the main street (z about -11 to 0) there. The board stands on the grass just across the street from that mouth, face south, so someone walking up the road from the jetty walks straight at it. Nearest building is the Pawn Workshop, 12 m east. About 57 m from where the harbourmaster stands.
- The thing in reach is `board.front()` with a 3.6 m reach (the board is wider). `Tallyport.paint` now also lights `ArrayMesh` parts (the torn stubs).

## 2. The board in focus (ux06)

- E at the board (`BountyBoard.open`): `Director.fly` eases the camera from where it is to square on the board in 0.8 s (smootherstep), at the camera's own fov, far enough back that the whole board fits with a margin. The player is frozen and faces the board (`rest_yaw`, `rig.hold_view`), their body is hidden once the camera is where they stand, and the energy plate and the HUD (map, pocket bar) fade to 35% in 0.25 s. The island stays.
- The cards are real paper in 3D (quads and `Label3D`s, lit like the town): a badge per kind (magenta "swap" for a sponsored swap, green "ens" for the sign quest, blue "?!" for the mystery, ink with the errand's first word, gold for Gran), the title lowercase in the serif, who pays, places left, "on Arkiv" in green when the publisher has the card, energy, and the fixed pay as "$0.04" in blue. One finished today on this machine is chalked "done" in green; a card you're on is only its torn stub on the pin.
- Left/Right (and A/D, Up/Down between rows) choose; the chosen card lifts 0.22 m off the cork and grows 12% in 0.3 s (quart out) and its pin turns gold.
- The island morphs into the board's bar (`Island.board_bar/board_card/board_hold/board_say`): the card's title in the serif, "N energy of your M", ← →, a ring with E that fills as E is held, "hold, tear it off", Esc.
- Hold E 0.8 s: `TakeQuest` goes; on the server's yes the card body tears off its stub (which stays pinned), swings down past the camera, the paper sound plays, the camera lands back on the player (0.8 s) and a slip of paper is in their hand for 1.6 s. Letting go early drains the ring. E has to be let go after the press that opened the board.
- Esc backs out. Refusals (`Refusals.say`) show in orange in the bar for 3 s in place of the energy line; "You're on this one" is said there without asking the server.
- The `BoardSheet` list is no longer used for the board (`BoardSheet` stays for the other boards).

## 3. A first goal and one tracked quest

- New `world/guide.gd` (`Guide`, made by `Tallyport`). One gold diamond (moved out of `QuestMarks`, which no longer draws any) over where to go next, the minimap's goal, and the island's standing line. Worked out every 0.3 s:
  - with quests on: the next step of the tracked quest. The tracked quest is the last one taken (`QuestTaken`), kept with `world._save_setting("tracked_quest")`; if it's gone, the first quest with a next step is tracked;
  - between quests: the Common Table when energy is under 40, your chest at your door when it's ready (only once you've done a quest), else the Bounty Board. So after Gran's letter the first goal is the board.
- The diamond moves every frame (a walking person is followed; the minimap goal too, updated when it moves more than 0.5 m). Past 14 m it grows with the distance (up to 2.5 times) so it still reads from down the road. Within 8 m it shrinks and sinks away (gone by 6.5 m), where the thing's own green key hint takes over.
- The island's rest pill widens and adds "NEXT  the Bounty Board  55 m" (Bitroad mono metres, rounded to 5 m, 10 m past 100; "here" within 8 m). The pill eases wider first, then the words fade in.
- The board's "done" chalk reads a "done today" list the Guide keeps from `QuestDone` (saved with the real day).
- `ui/strings.gd` P.S. and the harbourmaster's last line (`world/opening.gd AFTER_LETTER`) now say "Work's on the board where the road meets the town."

## 4. Quest done feels like a reward

- `world/sound.gd`: the coin plays for `QuestDone` and `RewardPaid` (one coin: the same sound within 0.28 s is dropped); `stamp.wav` plays for `HumanVerified` (the Town Pass).
- `ui/energy_plate.gd`: the wallet figure is Satoshi Bold beside a blue `$` disc, with "USDC" small. A new amount rolls over 0.4 s (quart out), and the change rises off it 18 px over 0.9 s and fades: mint "+0.04" for money in, orange for money out.
- `ui/island.gd`: `QuestDone` (a new "paid" kind that goes first in the island's line, like a meal) says "Paid · the chai round" with "+0.04" in mint and "into your wallet" when the Town Pass is stamped, or "Done · …" with "held for your Town Pass" when it isn't. The separate "Paid." moment for the same quest's `RewardPaid` is skipped within 15 s, so it isn't said twice.
- The first quest done still gets the full milestone blast (unchanged).

## 5. Fixes

- Place name under the minimap (`ui/game_hud.gd _where_am_i`): "The Landing" near the jetty, "Tally Square" near the square, else the nearest building from `world.json`'s sites (within 6 m of its footprint), else "Tallyport".
- Weekly strongbox (`world/door_chest.gd`): its USDC is read from `golden_drop`, shown as "Your streak bonus"; the dead `usdc` read is gone.
- `ui/food_menu.gd`: no Mei (no cook quote, "Asking for the thali…"), the kicker is "TODAYS MENU · LIVE PRICES" (Bitroad has no apostrophe) and the head "Common Table"; the old `MapData.SITES` read is gone.
- `ui/link_notice.gd` + `client/town_client.gd` (`trying`): the notice counts down for a nameless connection too.
- The ferry's ride clock (`world/opening.gd ride_held`, `ui/title_screen.gd`) holds under the logo and starts when the burst's wipe ends (`BootIntro.WIPE_TIME` after `opened`).
- "Leave" is not on the title menu in the web build (`OS.has_feature("web")`).
- `apps/web/app/play/page.tsx` passes `?server=` to the Godot iframe from `NEXT_PUBLIC_GAME_SERVER`, default `ws://127.0.0.1:7878`, `encodeURIComponent`-ed. (Someone else has since committed this file in 18bb100; I made no commits.)

## 6. The deck key strip

- New `ui/key_strip.gd` (`KeyStrip`), made by `Opening`: a small plate low in the middle while on the deck and ashore: W A S D "walk", Mouse "look", E "use", read from the real bindings. Each cap fades to 20% once used (mouse: 160 px of looking), each word once all its keys are, and the strip leaves for good when all are used; it is hidden while the ticket, handover and letter are up. It replaces the old "W Walk" hint after 6 s standing still.

## The bot

`game/dev/tallyport_drive.gd -- --arrive --player=b1run2` (headless, against the running --debug server): **79 ok, 0 failed** (it was 76; three checks added).

Bot changes: the board is used through `board.front()`, `board.is_open`, `board._choose(i)` and `board.take(i)` instead of the sheet. The first board visit holds E for real (`Input.action_press`) to tear the card off. New checks: the first goal is the Bounty Board, the taken quest is tracked, the wallet rolls to the new amount after `RewardPaid`.

New dev script `game/dev/board_shots.gd` makes the captures below (`tools/godot_d.sh --path game --resolution 1440x810 -s res://dev/board_shots.gd -- --arrive --player=NAME --shots-to=D:/dir`).

Note: another agent's windowed Godot run (pid 4968, started 02:14, stuck on a world.gd parse error that has since been fixed) held `godot.lock` for over 20 minutes, so my windowed captures ran with `GODOT_NO_LOCK=1`. I left that process alone.

## Captures

Small JPEGs, 720 wide:
- The board from down the road (26 m), the gold diamond over its roof, lamps lit: `D:/tmp/claude/D--code-dhaniverse-eth/639f1ab5-4f1f-4bb2-8149-2642134eedcc/scratchpad/b1/a_road.jpg` (zoom: `D:/tmp/claude/D--code-dhaniverse-eth/639f1ab5-4f1f-4bb2-8149-2642134eedcc/scratchpad/b1/a_zoom.jpg`)
- The board in focus: twelve cards, the chai round lifted, plates dimmed, the island as the board's bar with the ring half full: `D:/tmp/claude/D--code-dhaniverse-eth/639f1ab5-4f1f-4bb2-8149-2642134eedcc/scratchpad/b1/b_focus.jpg` (bar zoom: `D:/tmp/claude/D--code-dhaniverse-eth/639f1ab5-4f1f-4bb2-8149-2642134eedcc/scratchpad/b1/b_zoom.jpg`)
- A quest done: "Paid · the chai round +0.04 into your wallet" in the island, "+0.04" rising off the wallet: `D:/tmp/claude/D--code-dhaniverse-eth/639f1ab5-4f1f-4bb2-8149-2642134eedcc/scratchpad/b1/d_paid.jpg`
- The island's Next line, "NEXT your chest, at your door 55 m", with the minimap goal on its rim: `D:/tmp/claude/D--code-dhaniverse-eth/639f1ab5-4f1f-4bb2-8149-2642134eedcc/scratchpad/b1/e_next.jpg`
- The deck key strip: `D:/tmp/claude/D--code-dhaniverse-eth/639f1ab5-4f1f-4bb2-8149-2642134eedcc/scratchpad/b1/f_deck.jpg`

## world.gd

No edit. Everything hooks through `world.director`, `world.energy_plate`, `world.hud`, `world._setting/_save_setting`, `player.set_body_visible`, `player.rest_yaw` and `rig.hold_view` as they are.

## What's left

- Badges over the givers of quests you could take, and edge arrows for an off-screen goal (ux07). A dashed route on the minimap needs a path graph (none exists).
- A way to choose which quest is tracked (the phone's Quests page or the board); today it is the last one taken.
- The diamond folds away at 8 m but the key hint only appears in reach (2.6 to 3.6 m), so there is a short stretch with neither.
- The board's "done" chalk only knows what this machine finished today; the server doesn't say. All four errands still show every day (server).
- The wallet roll is on the wallet plate only; the island lobe doesn't fly money to it. No crate, receipt or medal (server work).
- The key strip's E is only used at the letter, where the strip is hidden, so the E cap is normally never ticked off; the strip goes with the opening.
- Mouse on the board's cards (click to choose) isn't wired; keys only.
