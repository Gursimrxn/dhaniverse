# Artifacts digest: what the design work made, and why

Read in full on 2026-11-07 from the six claude.ai artifacts (the Design canvases by file, the two plans by `index.html`), plus the founder's messages in the Claude Code sessions and the memory notes. Data only. Nothing was published, edited or deleted. Founder quotes are verbatim from the session transcripts; times are UTC as stored (the founder's clock is 5h30 ahead, so a message at 19:42 UTC on 6 Nov was written after midnight on 7 Nov, which is why some memory notes say 2026-11-07).

Artifacts (all private, owner: the founder):

| # | Name | Link | Last updated | Files |
|---|---|---|---|---|
| A | Dhaniverse Landing Baseline (main canvas) | https://claude.ai/artifact/NXZoisr29vwkuHyNoJkP6N | 6 Nov | 4 pages, 40 boards |
| B | Dhaniverse HUD (the "dynamic island") | https://claude.ai/artifact/SoWJXC5PfBLcs73ZPFkWzH | 2 Nov | 4 boards |
| C | Dhaniverse Brand Directions | https://claude.ai/artifact/Y36XDxHcm8gtJ9G5rcBrDE | 30 Oct | 16 boards |
| D | Dhaniverse title and settings | https://claude.ai/artifact/EeKiMEnSWLuWiK3NDr2dRN | 1 Nov | 2 boards |
| E | Tallyport Rewards Plan | https://claude.ai/artifact/JhguyU7FuZzZTSc39HZkoL | 5 Nov | HTML plan |
| F | Tallyport Technical Plan | https://claude.ai/artifact/GdPAAnZbUDK52RCBPcxB4K | 5 Nov | HTML plan |

`Artifact list` (scope all, limit 100) returned exactly these six; no other Dhaniverse or Tallyport artifact is visible. The founder said on 6 Nov 15:26 "read the chat, we had other artifacts from dhaniverse landing chat": those live in the claude.ai chats ("Dhaniverse landing page design brainstorm", "Game engagement and..."), which this session cannot read, and none of them is in the artifact list. Reason not found for anything that only exists in those chats.

Local copies of the files used here: `D:\tmp\claude\D--code-dhaniverse-eth\639f1ab5-4f1f-4bb2-8149-2642134eedcc\scratchpad\artifact-files\<artifact id>\project\` (A = `ae54712d…`, B = `d0f2bceb…`, C = `fb563041…`, D = `6e7cdab4…`, F = `7e8d82d2…`, E = `8f59b49a…`). Sizes of the live files match the copies.

---

## 1. The visual language, exact

There are **two surfaces** in the design work and the founder keeps them apart: a light web look (the landing) and a dark game look (the HUD plates). Mixing them is the thing he has rejected before (section 2, "founder reactions").

### 1.1 Brand tokens (identical in every artifact)

| Token | Value | Used for |
|---|---|---|
| Blue | `#0011FF` | money (USDC, always with `$`) |
| Green | `#337E43` | keys you can press, success, energy |
| Magenta | `#E100FF` | people, name tags |
| Orange | `#FF6600` | town events, warnings, refusals |
| Black | `#000000` | films, letterbox, loading |
| Cream | `#FFF8E3` | text on plates, paper, rings, keys |
| Paper | `#FAFAF8` | web page background |
| Warm paper | `#FFF7ED` | web gradient end, hackathon bands |
| Ink / plate | `#262727` | plates, text on cream |
| Gold | `#F0C33A` | in the Figma with no stated job. Game UX ux04 proposes: quest marker, medals, legendary. `Game_Layer_Design.md` lists it as an open question |
| Plate greys | muted text `#C9C1A6`; off pips `#3d3e3e`; rules `#3a3b3b`; dividers `#4a4b4b`; key lip `#9d9477`; row `#333434` | |
| Mint / orange-light | gain `#BDEDD0`, spend `#FF8A3D`; sun `#FFC86B`; text hover `#ffecbd`; slip paper `#fffdf6` | |
| Gradients (landing badges) | blue `#0011FF→#6DBDFF` (also `→#98B9FF` in d03); green `#337E43→#A7D2D4`; magenta `#E100FF→#BEB2FF` (`→#F9CFFF` in d03); orange `#FF6600→#FFA828` (landing `→#FFF7ED` orb, `→#FFBE8C` in d03); ink `#262727→#5d5e5e` | quest badges, orbs |

### 1.2 Fonts and the font blob ids

Real files live in `D:\code\Godot\dhaniverse-v2\apps\web\public\font`. Roles: Satoshi = headings and body; PP Editorial New (web stand-in Instrument Serif) = quotes, button labels, titles, paper; Bitroad (the same file the landing registers as "PP Mondwest") = keys, clocks, counters, big moments. Money is **Satoshi Bold**, not Bitroad (slashed zero misreads "100"; founder delegated this: "for the ui, you decide", 2026-10-31).

Blob ids are per artifact (each canvas has its own blob store), so the same font has a different id in A, B and C.

Main canvas A (landing, h01–h03, g01–g02, ux00–ux11 all use these):
- Bitroad 400: `cce21e5c49cfeb5839b9a03cbd14bd43` (metric overrides ascent 90%, descent 26.1%, line-gap 10%). Same blob also registered as `PP Mondwest`.
- PP Editorial New upright: `0044193d3c6d51bd5b901e372167e523` (registered as both 200 and 400; one file). Italic: `7bd4898b541eaa8654b08def423441b4` (registered as 200 and 400). Overrides 99% / 31% / 0%.
- Satoshi 300 `be1d489aa9d672adc557427d425b413b`, 300 italic `4d326ca4da4bf716546519afb8396737`, 400 `0dc3f4a36c1876a7e9197fb3861657d5`, 500 `1f346b731eeae28ffd208cfded1bae14`, 700 `489f14c4e8e522916d73a1b446646485`. Overrides 101% / 24% / 10%.

HUD artifact B (Main): Bitroad `278426ea3f3e9a6839bb7b00970e549d`, Mono `29bef466bee3931e289478ab4bc142ad` (clock), serif italic `81688f4d0a520a16b547cab39f53c05e`, Satoshi 700 `f13c38f27713c86cb0daae3cf92c1bda`. Brand Directions C also carries Instrument Serif (`a54c505f…` italic, `7427ce4a…` upright) and "Editorial" (`81aa7db4…` italic, `a29e8658…` upright).

Type rules seen: titles lowercase, letter-spacing `-0.05em`; accent word in Editorial 200 italic inside a Satoshi 500 headline ("learn money, earn it for realllll"); landing hero H1 68.65 px / line-height 62; section H2 48 px / 54; card title Editorial 32 or 34; body Satoshi 18 to 19 (`-0.05em`) at 75% black; small labels Satoshi 10 to 16 uppercase in a tag pill; HUD numerals Bitroad 22 to 30, money Satoshi 700 30 to 32; game scale on 1440x810: 60 · 38 · 24 · 16 · 13 · 11.

### 1.3 The landing's Apple-glass button (founder flagged it missing: "you are missing the apple glass like button even in the base landing page and other uis", 2026-11-06 19:42)

Reference: the hero "Play Now" (Figma node `1919:1603`, board `Main.dc.html`). Saved as memory `glass-button.md`.

- **Shell** (130 x 68): `border-radius 25px; background rgba(255,248,227,.10); box-shadow 0 5px 76.4px rgba(255,255,255,.25); backdrop-filter blur(60.85px); outline 1px solid rgba(0,0,0,.10); outline-offset -1px`.
- **Inner pill** (at 10,10, 110 x 48): `border-radius 17px; background linear-gradient(360deg,#000000 0%,#666666 100%); box-shadow 0 4px 12.9px rgba(0,0,0,.25)`.
- **Label**: PP Editorial New 400, 16 px, `letter-spacing -0.05em`, `#FFF8E3`, line-height 14.4, at left 16, top 16.
- **Arrow**: image blob `58a5e27b6a13393e07807a2156d3a776`, 8 x 10 at (82,19). (Secondary variant uses `588fa46f74f623d6107eb60cefd688fd` at (101.5,19).)
- **Highlight image**: blob `150c05f47e50da1180244c6ccfadab8c`, 114 x 52 at (8,8) over the pill, `pointer-events none`. Footer pair uses blob `caf62b6527ba2855faa610572b786d13` (134 x 52 at -2,-2 on "Play Now", at -2,62 on "Invite People").
- **Footer variants** (d12 and m12): "Play Now" = black-to-grey pill 130 x 48 radius 17, no outer shell; "Invite People" = `border-radius 17px; background linear-gradient(360deg, rgba(255,255,255,.1), rgba(102,102,102,.1)); backdrop-filter blur(26.7px)`, white label. Hero (d01/m01) uses blur 60.85 and the full shell. Hackathon hero h01 copies the shell **without** backdrop-filter and without the highlight image.
- Other glass on the landing: `Main` hero blur band `blur(5.15px)` over a near-transparent gradient (radius 80); d03 blurs 17.14, 20, 27.37; d10 blur 113.6; hero glow image `1d3d12cf18fc35710ec9fd76132196d7` at opacity .5, `mix-blend-mode screen`, `filter blur(35.15px)`.

### 1.4 Landing components (light, web only)

- **Page**: `#FAFAF8` with a rounded section sheet: `border-radius 120px` (mobile 60), `linear-gradient(180deg,#FAFAF8,#FFF7ED)`; highlights band `linear-gradient(360deg,#F9F7EC,#F4F2FF)`. Hero image 1728 x 925 `radius 120`, fades to `#FAFAF8` over its top 561 px.
- **Section tag**: 178 x 43, `radius 15`, `linear-gradient(180deg, rgba(0,0,0,.1), rgba(102,102,102,.1))`, Satoshi 16 uppercase (mobile 10).
- **Pills**: social proof "1.7k+ players Worldwide" 236 x 42.8, `radius 44`, `rgba(255,255,255,.65)`, outline `rgba(0,0,0,.05)`, three 26.8 px avatars overlapping 20 px, Editorial 16. Hero chips 36 px high, `radius 12`, `#FFF8E3`, outline `rgba(0,0,0,.05)`, 32 px square icon `radius 10` in a brand colour (Bitroad 10 to 12), label Satoshi 500 10 to 12. The loud chip: `linear-gradient(90deg,#FFA828 54%,#FFC774 66%,#FFA828 75%)`.
- **Cards**: `radius 60` (d02), `80` on 380 x 380 (h02), `60` on 680 x 300 (h03); `linear-gradient(180deg,#FAFAF8,#FFFFFF)`; `outline 1px rgba(0,0,0,.1)`; alternating tilt `-1.62deg` and `2.74deg`; 74 px orb (`radius 50%`, brand gradient + illustration blob: orange `c4f83e63…`, green `8735bd01…`, blue `6409c67e…`, magenta `72b21abc…`); title Editorial 32 lowercase; body Satoshi 19/25. h03 badge 120 x 120 `radius 40`, Bitroad 44. Footer card 400 x 1079 `radius 60`, white, `box-shadow 0 24px 92.9px rgba(0,0,0,.25)`.
- **Logo**: mark blob `09a745e89309dce196c11a83f1de0612` (19.81 x 19.33) + wordmark blob `8583e279c875dfaf33a8b9a630e366c3` (106.86 x 17.95), centred at y 29 in the hero, left-aligned in the "rest of site" header (with a 19 x 17 icon `2c60441766b3347b66e6431e9a51bf2e` on the right).
- **Scroll ring**: blob `67a5bd9cfa4333f0e2b70782053bcdb6` (62 x 36) at (833,896). Hero town image blob `1c8e8b7a471b6aff492329737aba9105`.
- **Radius census across the landing**: 40 (54 uses), 20 (51), 60 (27), 120 (26), 80 (19), 999 (16), 18, 10, 54, 48.5.

### 1.5 Game components (dark, in the 3D world)

- **Plate**: `background #262727; border-radius 20px; box-shadow 0 0 0 3px #FFF8E3, 0 10px 16px rgba(0,0,0,.35)` (HUD board uses `0 1rem 2.4rem .28` shadow in rem). Pill variant `border-radius 999px`. Only where words sit on the moving world.
- **Key cap**: min 26 (24 in ux) square, `radius 8` (7), `#FFF8E3`, ink text Bitroad 13 (12), `box-shadow inset 0 -3px 0 #9d9477`; sinks 2 px when pressed (`inset 0 -1px`, `translateY(2px)`).
- **Key hint tag**: `#337E43`, white Satoshi 500 14, padding `6px 12px 6px 6px`, `radius 12`, 2.5 px cream ring, 8 px tail; pops from scale .8 in 150 ms. In-world "E" pill in B has a cream tail.
- **Name tag**: `#E100FF` with black text, Satoshi 500 14 (13 small), radius 9 to 12.
- **Energy pips**: 10 pips, 14 x 8 (13 x 8 in ux02), `radius 4`, on `#337E43`, off `#3d3e3e`; last pip `#FF6600` breathing 1.6 s under 20 (B: 22 x 14 pips, 5 pips and 2 gold bonus dots `#F0C33A`).
- **Amount**: 26 px `#0011FF` disc with white bold `$`, Satoshi 700 30 to 32, gain in `#BDEDD0` beside it, spend `#FF8A3D`. Wallet cap label Bitroad 10 to 13 `.14em` `#C9C1A6`.
- **Face ring**: 72 px conic gradient `#337E43 0 72%, #3d3e3e 72% 100%`, 60 px magenta-to-lavender portrait inside.
- **Minimap**: round plate 170 (g01), 176 (ux02), 188 (B/C), 200 to 220 (ux07); roads `#5C5642`/`#8c8471`/`#d9cfb0`, water `#2f5d8a`/`#2d5b8a`, buildings `#3d3e3e`/`#59604f`, gold diamond `#F0C33A` stroke `#262727`, N badge, place-name pill.
- **Pocket slots**: 60 (g01), 46 (ux02), 68 (B hotbar); `radius 16 / 13`, ring 3 / 2.5; count badge cream round; key letters or numbers in Bitroad.
- **Price tag**: dark plate, cap "THALI", Satoshi 700 20 `$0.024`, orange `▲ 3%`; split-flap flip (B HudMotion, g01).
- **Stamps**: "TOWN PASS" `2px #337E43` border radius 6, `#BDEDD0`, `rotate(-4deg)`; "AT THE CHAIN" cream tag, `#FF6600` border and text, `rotate(-3deg)`, `.12em`; receipt "ON CHAIN · 0x9f…c21" `#337E43`, `rotate(-5deg)`.
- **Paper**: `#FFF8E3` (slip `#fffdf6`), ink text, `radius 4`, `box-shadow 0 18px 30px rgba(0,0,0,.45)`, scalloped edge `radial-gradient` 12 px, tilt -2 to +1.5 deg, held to camera then pocketed. Rows dashed `#c9c1a6`.
- **Toast**: `#FF6600`, black text, radius 16, 3 px black timer bar shrinking linear (5 to 8 s), drops in 0.5 s.
- **Badges** (full-screen menus only): 76 to 104 px, `radius 24 to 34`, brand gradient, ring 3 px cream in dark boards; Bitroad label (`90s`, `swap`, `ens`, `?!`, `crane`, `post`).

### 1.6 Motion

- Out curve `cubic-bezier(.2,.9,.25,1)` (everything; 49 uses in B), in curve `cubic-bezier(.4,0,1,1)` (ux11), HUD extras `(.4,0,.2,1)`, `(.3,1.25,.5,1)` (overshoot), `(.3,.7,.3,1)`. Nothing linear except timers.
- Timings: key hint pop 150 ms; plates 250 ms; number roll 400 ms (B: 520 ms; "+" gain rises 900 ms); island lobe 500 ms (staged 0, 90, 180, 310, 500 ms with a goo filter in B); box 0.9 to 3 s; money-in 3 s, bank 5 s, mentor 8 s, town 3 s, month slip 6 s (B); sun cycle 33.9 s; map goal ping every 2 s; hotbar lift 8 px; pips 70 ms apart; low-energy breath 1.6 s; chest breath 4 s ("never a pulse").
- **Milestone blast** (C board 10; the thing he asked to keep): background = chosen brand colour; 0.1 s mark pops 0.7 s; 0.25/0.45/0.65 s three shockwave rings 1.2 s to scale 3.4; 0.45 to 0.6 s 40 confetti 1.8 s in brand colours; 0.35 s kicker "MILESTONE · A NEW FIRST" Bitroad 22 `.16em`; 0.5 s title Bold 120 `-0.045em` stamps from scale 1.9, rotate -6deg, blur; 0.55 s shake 0.4 s; 0.95 s underline 0.6 s; 1.1 s shine loop 2.4 s; sunburst rays 40 s; count-up 0.9 s ease-out cubic; stats row with 8-segment bar; buttons at 1.3 s; "NEXT FIRST" plate at 2.1 s.
- Scale rule: every screen in a 1440x810 design space, `1rem = 10 * min(vw/1440, vh/810)`, fits 810 tall ("designs are exceeding screens", 2026-10-30 04:49).

---

## 2. Per artifact: link, session, reason, boards, status

### Founder reactions that decide status (chronological)

All times UTC. Session `e2b97857` = the design session ("/design" started 30 Oct 03:25); session `639f1ab5` = this session.

- 2026-10-30 03:33, on the first pass (light, invented palette): "NOO i hate this. this is so off from the original design that i gave you. these are the five colors of dhaniverse. the fonts, and everything is off, you destroyed the whole brand guidelines. and didnt you read the blueprint i shared"
- 04:06: "we need to improve the game hud more, and actually make it like a game hud not some ui elements".
- 04:14: "it still feels very basic compared to our landing page... the spacing etc is very random in your designs."
- 04:29, after a light paper/glass HUD restyle copied from the landing: "NOOO i liked the earlier hood wayy better. the toasts, and everything. now you fucked it up" (memory `game-hud-style.md`: the dark plate with 3 px cream ring is the liked HUD).
- 04:33: "i like this version, this ui needs to go way above, not below like earlier version. keep this look yes. but improve it... milestone looks good, can be more improved for more dopamine hit."
- 04:49: "it is getting a little worse rather than cool sick minimal animations... there are still some sizing issues and responsiveness issues, the designs are exceeding screens."
- 04:54: "i dont think everything needs a border and background. let have some creativity in the designs."
- 05:53: "the milestone was so dopamine giving earlier, keep it like that. the blast and stuff."
- 17:55: "i think i like the earlier atm screen you made, but as a popup when clicked on atm screen with a tv filter... town event, i am a bit dicey about it... but it is bad. and keep the mentor chat as it is for now, i like the current ui."
- Memory (same two days, exact times not in the transcript text I could extract): title and arrival screens "look so ai generated" (no spaced mono kicker + giant headline + paragraph + stacked buttons); full-screen boards on gray backgrounds "looks the same and boring... what is the difference between them and just a basic animated website?" (make UI live on real world objects with a physical action).
- 2026-10-31: "for the ui, you decide and the brand directions, you should evaluate on what feels much better".
- 2026-11-01 12:20: "it feels very non-game like, and it needs a better cinematic touch... serving people in that market is not the main objective, it is, teaching players about money through consequences".
- 2026-11-01 17:49: "the uis in the game does not match the figma document you made. like totally different." 18:14 (title): "oh my god the logo zoom out animation is sick... show a black screen as loader first, then show the dhaniverse logo with animation and the dhaniverse text, then disappear the 'dhaniverse' and make the logo come in center, then do this animation and then boom we will start the game." 18:24: "the settings page is ass. it needs to keep up to the quality".
- 2026-11-02 13:29 to 13:53 (island): "what you think like a dynamic island like center top hud bar?" then "Design it first", then "looks good, it should also act on hover", then "should we make this sun to show the sun position? and add more micro animations in the whole hud experience. you can go creative as much as you want".
- 2026-11-05 19:42 to 22:39: "I am not going to keep any fake currencies anymore"; "remove the trash we dont need... very fast paced like fucking casino type vibe"; 19:57 "i am thinking to keep the walking around, and keep the ai mentor, and keep all the stuff in the plan like quests and stuff"; 20:32 "ok, we dont need the atm screen as well".
- 2026-11-06 09:33: "these artifacts are old... the whole game is kind of changed". 15:17: "lets work on the ui and the artifacts and the newer visuals stuff according to the plan". 15:26: "read the chat, we had other artifacts from dhaniverse landing chat."
- 2026-11-06 18:51 (/design brief): "the current godot ui and ux is shit, so read all of the artifacts, lets design our ux."
- 2026-11-06 19:27 (on ux00 to ux02): "the designs are still very basic, the game layer, the walkflow of the full game is still very bad. like how will player know? like, player will login through world, then he will see the quest board (need very good ui), and he will then solve the quest, then he will get random lootbox, and he will get money from that lootbox. just like how predict.fun does the lootboxes. more better ui, maybe something from our baseline landing page. we have some bank balance and other ui stuff right?"
- 2026-11-06 19:42 (on ux01, ux02, ux10, ux11): "you are missing the apple glass like button even in the base landing page and other uis if needed... after watching these ui designs that you are giving, needs to be read correctly of all of our artifats and what they made and for what reason. and for this: you need to read all of the code correctly."

### A. Dhaniverse Landing Baseline (main canvas)

Made 2026-11-06 in three steps: (1) a delegated session "Rebuild the Figma landing page as an artifact" (cwd `D:\code\Godot\dhaniverse-v2`) with the brief "rebuilt as an Artifact so they can decide changes to it later, next to the original... faithfulness matters more than polish... Don't change or improve anything" from `figma/landing.json`, `figma/images`, `figma/svg` and `D:\m\Dhaniverse.fig`; (2) this session, at 15:21 UTC, added the hackathon landing and Game UI pages after the founder's 15:17 "lets work on the ui and the artifacts and the newer visuals stuff according to the plan"; (3) this session, after the 18:51 `/design` brief, added the Game UX page. Each board carries a Figma node id comment, so the baseline is 1:1 and editable section by section.

**Page "Current landing" (23 boards, 1:1 from the Figma, status: current baseline, the reference for all web styling).** Desktop 1728 wide, mobile 402 wide.
| Board | Shows |
|---|---|
| d01 Hero (Main) | Town image from the hills with glow overlay, centred logo, "1.7k+ players Worldwide" pill, headline "Experience Life,", "Click to Manifest" chip, "4x Global hackathon winner" chip, glass **Play Now**, scroll ring |
| d02 What's Dhaniverse | Tag pill, "It's basically real life… except bankruptcy isn't a personality trait here", four tilted cards: play with the world, Living Economy, personalised growth, Event Simulations |
| d03 Product overview (3898 tall) | "The bank of Dhaniverse": card `**** 1234`, Send Money, Request Money, transactions list, Credit Score 710, Add Balance, Account Balance, diversification (Equity, Estate, Mutual Funds, Crypto, Options, Bonds). This is the "bank balance" UI the founder points at on 6 Nov 19:27 |
| d04 Training arc | "main character" strip |
| d05 Your leverage | Topic cloud: Budgeting, Credit management, Investing, Taxation, Compounding, Debt, Retirement, gig economy, "40+" |
| d06 Highlights | Podium: Hackmol 6.0 (NITJ) 1st, ICP WCHL Europe 3rd, Poland & Ukraine 4th, Honourable mention Global Finale (Editorial 64) |
| d07 Testimonials | Testimonial wall |
| d08 Done so far | "here is what's already been done so far" update tiles, Join Discord |
| d09 Discord | Community members, "Join Discord" |
| d10 Text memos | Chat-bubble wall "Read all 3,456 text memos" |
| d11 FAQs | Seven questions (game or something else, need to know finance, play with friends, India only…) |
| d12 Invite + footer | "Why aura farm alone?" with Play Now and Invite People glass buttons, footer columns explore, our-spot, legal, "Still EXPLORING. Still learning......" |
| m01 to m12 (10 boards) | Mobile versions of 01, 02, 03, 04, 05, 06, 07, 09, 11, 12 |
| header-states | "Header Hero" (centred logo) and "Header rest site" (logo left, icon right) |

**Page "Hackathon landing" (h01 to h03; status: current draft, light web style, USDC-only, all copy matches the Technical Plan).** Made 6 Nov at the founder's "newer visuals according to the plan".
- h01 Hero: "learn money, earn it for realllll.." with pill "Built at ETHGlobal Mumbai", sub "A little town where every quest pays real USDC, every meal moves a live Uniswap market, and your name is yours on ENS.", four chips (USDC only, no play money · Every meal moves the price · Your name, on ENS · The town lives on Arkiv), the shell of the glass button without backdrop-filter or highlight.
- h02 The town: "every coin here is real USDC… so maybe don't spend it all on snacks"; cards eat to play, quests that pay, nobody gets stuck, yours on chain.
- h03 Quests: four 680 x 300 cards: market rush (90s, 0 energy, top 10 split the pot), the spice run (30 energy, cargo back + $0.50), paint your shop sign (20 energy, sponsored), the daily mystery (50 energy, $0.50 to $5).

**Page "Game UI" (g01, g02; status: current, but partly superseded by ux02 and ux09).**
- g01 The HUD with USDC (1440x810 on a stand-in town image): You plate with face ring, ENS name `asha.dhaniverse.eth`, 10 pips, "72 energy · +1 in 2:41", "Free meal ready in 3:10"; Wallet plate "WALLET $4.27 USDC" with TOWN PASS stamp and "Owed $0.50 · Spice Run, paying at the chain"; orange "Rehearsal town: the money isn't real"; island pill 200 x 48 "9:40 | Day 12" with sun dial; 170 px minimap + "Tally Square"; mentor plate "Food is cheapest right after the harvest." with `H`; green "E Open your chest" tag; magenta "kofi · Hall Trader"; THALI `$0.024 ▲ 3%` tag; cream "AT THE CHAIN" stamp; six-slot pocket bar numbered 1 to 6 with counts. Purpose: show the plate language carrying USDC.
- g02 Chests: spawn, open, golden drop: light page `#FFF7ED` with four tilted white panels (radius 48) each framing a dark scene. 1 "a crate turns up" (proposal: a few lucky crates spawn around town each day at server-picked spots, no energy, a daily cap, 4 s breath); 2 "the chest at your door" (brass bands after a 3-day streak, gold after 7, ten rivets around the lock with seven lit, brass odds plate: Energy 20, Tickets 2, Meal voucher 1 in 4, Golden drop 1 in 10, "Nine rivets lit: the next one has a drop."); 3 "opening, in three seconds" (timeline 0.0 latch, 0.5 lid, 1.0 energy, 1.35 tickets, 1.7 voucher, 2.05 drop; any key skips); 4 "the golden drop" (gold light, three rings, confetti in the five brand colours, a stamped "golden drop" title, wallet counts `4.32 +0.05`). Statement: "Every chest is paid from the house pool's surprise bucket, never from what a player spent, and never sold. The server decides what's inside before the lid moves." This is the only chest design that follows `Game_Layer_Design.md` Part 3.

**Page "Game UX" (ux00 to ux11; the new drafts being criticised).** Reason: the 18:51 brief above. Per-board detail and critique in section 4. Note the canvas titles do not match the file names: ux01 is titled "UX · 11 Why", ux02 "10 The HUD", ux03 "06 Step 3", ux04 "01 Game brand guidelines", ux05 "02 Step 1", ux06 "03 Step 2", ux07 "04 Quests marked", ux08 "05 The town map", ux09 "07 Step 4: the box", ux10 "08 Step 5: the wallet", ux11 "09 Motion". The `<title>` inside each file is a third numbering.

### B. Dhaniverse HUD, the "dynamic island" (4 boards)
Made 2026-11-02 in session `e2b97857` after "what you think like a dynamic island like center top hud bar?" / "Design it first". Reason: replace scattered corner plates with one morphing centre element, plus the founder's hover request, sun position and micro animations. Status: **liked** ("looks good, it should also act on hover"); mostly **superseded in content** by the USDC-only plan (coins, months, EMI) but the mechanics are the reference.
- **Main "In the game"** (interactive, 1440x810): one dark pill at top centre that morphs. Rest: Mono 22 clock + "Month 1" + sun dial. Moments: "Paid. Order served · Kofi's stall +12c · cash 160c", "Spent. Chai −19c", "The bank moved. 3.75% from 3.50%", mentor "A thought." with `H · Ask`, town "[name] bought a flat.", month-close tear-off slip (`#fffdf6`, scalloped). Glance card on hover or Alt: CASH, SAVINGS, ENERGY 80/100, THIS MONTH +36c/−19c, JUST NOW log, key row `H Mentor · N Paper · Tab Phone`. Headline serif italic 25 px; figures Bitroad 32; plus `#BDEDD0`, minus `#FF8A3D`; sun cycle 33.9 s; a cream-gradient "sheen" variant.
- **States "Every moment"**: durations money in 3 s, out 3 s, bank 5 s (jumps queue), mentor until H or 8 s, town 3 s (last), month slip 6 s, shift holds the island ("Paid this shift 36c · 4:12 LEFT"), waiting dots under the island, sky variants Dawn/Noon/Dusk/Night, glance.
- **Morph "How a moment opens"**: same moment at 0, 90, 180, 310, 500 ms; lobes split from the pill (widths 24.1 to 33.5 rem; SVG goo filter).
- **HudMotion**: nine 4 s loops: coin turns once, digits roll 520 ms, "+12c" rises 900 ms, energy pips fill 70 ms apart and a fed dot pops, low energy breathes 1.6 s `#FF6600`, savings mint glint 700 ms, map goal ping every 2 s with place name roll, hotbar slot lifts 8 px with ring draw and 94% press squash, goals tick draws and slides, key hint pops 220 ms, station-board price flip.
- Includes a `SKILL.md` (Design type instructions).

### C. Dhaniverse Brand Directions (16 boards)
Made 2026-10-30 to 2026-11-01 in session `e2b97857`. Reason: the founder brief "brainstorm me on this and give some brand design ideas, also to the game ui by taking the reference of this"; the first pass was rejected for inventing the brand, then rebuilt from the five colours. Status: the HUD, milestone and mentor boards **liked**; Event **"a bit dicey... bad"**; Bank ATM **liked as a popup with TV filter** then **dropped on 5 Nov ("we dont need the atm screen")**; every coin-priced board **superseded**; Landing board 2 **superseded** by the real Figma baseline (A).
1. **Brand guidelines**: five colours, logo (two linked loops, `brand-mark.svg`, gradient stops TODO), type (Satoshi 68 Bold hero, 40 to 48 titles, Editorial 32 quotes, Bitroad ~16 product UI). Marks `brand.gd` teal/gold as old, not brand. Current.
2. **Landing**: update tiles (radius 32), testimonials, trophy podium, memo wall, green CTA (radius 40). Superseded by A.
3. **Title**: pixel coast, mark 96 + wordmark 112, menu Continue / New life / Settings, PRESS ENTER pulse 2.4 s, "DEMO BUILD · ETHGLOBAL MUMBAI". Superseded by D.
4. **Arrival (Rosa)** "+100c", rent. Old economy; founder hates the name Rosa (memory 2026-11-01).
5. **HUD exploring**: portrait 92 + health ring, 5 energy pips + 2 bonus dots, blue coin disc "84c", clock plate, orange toast with 6 s timer, round minimap 188, "NEXT, IF YOU LIKE" list 0/9, feed, 5-slot hotbar (68 px, lift 8), key hints, green "E · Enter the Market Hall" pill. **Liked** (the "earlier hud" of 04:29). Currency obsolete.
6. **Shift** (Kofi's stall, 2:00, streak, patience): old economy; founder: serving people in the market is "not the main objective".
7. **Common Table**: prices moving every 5 min, "if you eat this now" panel. Mechanic still true (energy from food), priced in coins.
8. **Bank ATM**: touch-to-start, steppers, statement printout. Old; removed from plan 5 Nov.
9. **Ledger Wall**: carve a first, hold E. Still in Game Layer ("The Wall").
10. **Milestone**: the full blast (section 1.6). **Liked and ordered kept** ("keep it like that. the blast and stuff").
11. **Town event**: HARVEST GLUT banner, price tags -20%, three choice cards, orange toast 8 s. "dicey... bad".
12. **Mentor chat**: three numbered answers with feedback ("noted / fair enough / she'll ask again tomorrow"). **Kept** ("i like the current ui"); 5 Nov "keep the ai mentor".
13. Loans (Dario). 14. Town project (bakery). 15. Rest (recap, rent, interest). All coin life-sim: **superseded**.
16. **Library**: free course, "The Open Notch". Superseded with the life sim.

### D. Dhaniverse title and settings (2 boards)
Made 2026-11-01 18:04 to 18:30 in session `e2b97857` from the brief "design a title screen, settings page, do not make the settings page cover the full screen, let the game visible, use latest ui practices... smooth animations, motion graphics. all the sauces." Status: Title **liked** ("the logo zoom out animation is sick"); Settings first version "ass", the board in the artifact is the later redo (no further comment).
- **Title (interactive)**: black loader, progress line 220 px fills 1.1 s; mark spins in at 26% of 4.3 s (scale .2, -90deg, overshoot), wordmark slides out and back, mark pulses, boom ring (140 px to scale 16 over 1.3 s) at 4.2 s, cream flash 1.5 s, iris mask opens from the mark (6.2 s) onto the ferry at dawn (24 s push 1.34 to 1, rays, bloom, 14 motes, grain, letterbox bars 52 px). Wordmark 170 Bold with a colour sheen every 7 s. Menu Editorial 48, hover rolls to italic `#ffecbd`, orange tick 36x5: Continue, A new life, Settings, Leave. Right "Tallyport, live" plate (`[n] in town`, spark line, "Food today 10.20", "The bank's rate 5.50%"). News ticker 60 s. Legend `↑↓ Choose` `Enter Go`. Mouse parallax. Matches the founder's 1 Nov opening order (black, logo, boat docks, then menu).
- **Settings over the game**: tabs Picture / Sound / Controls / Game; hold-to-compare BEFORE/NOW; Quality Low/High/Full; sliders Brightness, Colour, FOV; toggles light rays, cinematic camera; 28-bar sound meters; key rebind with keyboard map; key hints, mentor speaks up, subtitle size; "Esc · Back to the town". Game stays visible behind it, as asked.
- Out of date: "month 14", "Your money waits for you", ticker lines on flats, "Coins and bells", "Take money out Q / Scooter F". `Game_Layer_Design.md` drops Leave and a scrolling ticker.

### E. Tallyport Rewards Plan (marked REPLACED, Arc version)
Made 2026-11-05 (hackathon plan, before the pivot). Reason not found beyond that it was the rewards half of the plan. Status: **superseded** by the USDC-only Technical Plan and `Game_Layer_Design.md`. Content: LootGO study, funding sources, six rules, partner tracks (Arc, World, Uniswap, ENS backup), 36-hour plan, 4-minute demo, risks; reward loops in section 3. Arc contracts and "game coins" tickets are dead.

### F. Tallyport Technical Plan (v2, ETHGlobal Mumbai)
Made 2026-11-05. The local `docs/planning/Dhaniverse_Technical_Plan.html` is the **newer** truth; the artifact differs in: two currencies (USDC plus gold "coins" for the life sim) vs USDC only; "Life sim" row at 0 energy; chests "loot, golden coins" vs "golden drops (USDC), tickets"; "learning never needs energy" vs "walking, talking, Rush, chests, Pass cost zero"; "36 hours / Classic track / Tallyport keeps the yield" vs "the build / Dhaniverse keeps the yield". Numbers match. Founder, 2026-11-05: "I am not going to keep any fake currencies anymore". **Superseded by the local file.**

---

## 3. Rewards, lootbox and chest designs across the artifacts

| Source | What it designs | Money rules | Status |
|---|---|---|---|
| E Rewards Plan | **Tally Chest**, daily, waits at your door, hold to open, lid rattles, items fly to pocket; streak 7 upgrades wood/brass/gold, one missed day a week forgiven; golden coin $0.10 to $1 USDC or sponsor token; budget = min(campaign left / days left, daily cap); plus Market Rush (serve-orders, ghost), Bounty Board, Grandma's Ledger, Lucky Ledger (1 ticket per 100 coins), Rate Call, Town Goal, referral tickets | Arc, game coins | Superseded |
| F Technical Plan (local) | 5-of-7 login streak opens a weekly chest; pity: every 10th chest without a golden drop guarantees one (or a meal voucher); house pool 4% of balance per day: 30% Rush pot, 20% streak bonus, 15% errands, 20% chests/golden drops, 15% mystery and events; food revenue 60% pool / 10% safety net / 20% ops / 10% team; random rewards only from sponsor fees, drops and yield; chests never sold | USDC only | Current base |
| C board 10 Milestone | **The blast** (section 1.6) as a reward moment for a first | coins ("50c") | Liked; keep sequence, retarget to USDC/Town Pass |
| C board 11 | Choice cards as the nearest thing to a reward decision | coins | Dicey |
| B HUD | Island lobe "Paid. +$", receipts tear-off slip, digit roll + rising gain | coins | Liked mechanic |
| A g02 Chests | **Four-step chest**: crate spawn (daily, server-picked, 4 s breath), chest at door (tier by streak 3/7, ten pity rivets, brass odds plate), 3 s opening timeline, **golden drop with the full blast** | USDC 0.05 | Current, matches `Game_Layer_Design.md` |
| `Game_Layer_Design.md` Part 3 | Wood 10 energy / 1 ticket / 1 in 10 voucher / 1 in 20 drop; Brass (3-day) 20 / 2 / 1 in 4 / 1 in 10; Gold (7-day) 30 / 3 / 1 in 2 / 1 in 5; drop = 0.05 USDC; weekly strongbox 5 of 7 pays 0.25 USDC + 3 tickets + 30 energy; "No wheel to spin for USDC"; rule 5: random USDC only from free things, "no quest reward is random"; rule 1/2: quest pay fixed on the card, skill decides medals not USDC | USDC only | Current base |
| A ux06/ux09 | **Box after every quest**, rarity Common 55% $0.02 + ticket / Rare 30% $0.10 to $0.50 / Epic 12% $0.50 to $1.00 + title / Legendary 3% $2.00 full blast; pity 10th box without an Epic is an Epic; quest fixed pay lands first on its own receipt, box is extra; "Boxes are never sold. No keys, no paid odds, no rerolls." | USDC; amounts "proposals until set in rules.toml" | Draft; implements the founder's 19:27 request, contradicts Game Layer rule 5 and the chest tiers |
| A ux10 | Tickets and meals counted in the wallet, "never money" | | Draft |

The only milestone/blast treatments that exist: C board 10 (full sequence), g02 panel 4 (golden drop). The only physical chest art: g02 (wood body `#7a4f27`, brass bands `#C9A24A`, rivets `#FFC86B`). ux09 uses a blue box with a `#F0C33A` strap.

---

## 4. What ux00 to ux11 get wrong or miss

Verdict first: the ux set is a coherent walkthrough (sign in, board, quest, box, wallet), uses the brand tokens correctly, keeps the dark plate and cream ring for the HUD, and answers the founder's 19:27 flow. But it re-invents rather than reuses much of what earlier boards already settled, drops things the founder explicitly kept, and re-introduces the web look he rejected for the game. Findings are concrete and checkable in the files under `A/project/`.

### Across the whole set

1. **No glass button anywhere** (founder flagged 19:42). Search of all twelve files finds no `backdrop-filter`, no black-to-grey inner pill, no highlight image `150c05f4…` or `caf62b65…`. Buttons are flat: ux06 "Take it" is a `#337E43` 18-radius button and "Practise free" a `#3a3b3b` one; ux05 has an underlined link and a `G` key; ux00 to ux04 have none. ux04's "Surfaces: three, never more" (plate, paper, badge) and "Parts" list omit it, so the brand sheet itself teaches the omission.
2. **Quest board and lootbox "something from our baseline landing page"** (19:27): ux06 does borrow white cards (radius 30, `#FAFAF8→#FFF`, Editorial 200 lowercase titles, gradient badges) but not the landing's tag pill, tilt `-1.62/2.74deg`, 60 to 80 px radii, glass button, or the d03 bank card language. ux09 and ux10 use none of the landing look: ux09 is a dark box on a navy radial; ux10's balance card is a `#0011FF→#2a3dff` gradient with bars rather than the d03 "bank of Dhaniverse" card (card number, Send/Request Money, Account Balance, transactions) the founder points to ("we have some bank balance and other ui stuff right?"). The d03 board is never referenced.
3. **Web-landing tropes the founder rejected for game screens** (memory `game-hud-style.md`: "look so ai generated: spaced mono kicker + giant headline + paragraph + stacked buttons"). Every ux board opens with a Bitroad kicker at `.14em` ("THE GANGWAY GATE · STEP 1 OF 5", "PROPOSAL · ANY QUEST, ONE RHYTHM", "PROPOSAL · TAB, THEN WALLET", "MOTION · EVERY CELL IS LIVE") then a 40 to 76 px headline then a grey paragraph. ux05 is the worst: kicker, 76 px headline "one person, one pass", paragraph, three stacked icon rows, plus a modal card on the right.
4. **Full-screen boards on blurred grey/dark backgrounds** (the "basic animated website" complaint): ux05, ux06, ux08, ux10 are full-screen panels over a blurred or darkened town image, with plates and cards, not UI on real world objects with a physical action (ATM slot, crate, gate, stone slab, the chalk slate, the Bounty Board on Tally Square, the chest at your door). `Game_Layer_Design.md` assigns the Bounty Board, Common Table, strongbox, Draw drum to "World". ux06 is "Screen"; the founder's wording in the same message is "quest board (need very good ui)", so a screen is defensible there, but there is no view of it on the real prop in Tally Square (ux02 shows only three tiny cards on the board).
5. **Missing boards for things the founder already approved or praised:** Title and opening ("the logo zoom out animation is sick", black loader, logo, text vanishes, mark centres, boom); Settings; mentor chat (kept on 30 Oct and 5 Nov) including the `H` plate; the milestone blast (first quest done, Town Pass); loading screen ("where did our loader go?"); town event / harvest toast and price tags as boards; Common Table food purchase and the Uniswap quote (the plan's core "eat to play" loop, the h02 headline); dialogue box with harbourmaster and Gran's letter; low-energy and refusal states (ux04's voice rule "A refusal says why" has no board); the Spice Run's swap screen with fee and slippage in plain words; Market Rush's trading sprint; the Wall, Town Goal, Price Call, Draw Night.
6. **Colour jobs contradict themselves.** ux04 says "every colour has a job" (blue money, green go, magenta people, orange heads up, gold next) and "Rarity, low to high ... Never a fifth", then maps rarity to cream / blue / magenta / gold, reusing money-blue, people-magenta and next-gold. ux09's Rare box is money-blue with a `$` disc in the same blue; ux06's "EPIC BOX" is the people colour. Gold is also used for medals, quest markers, legendary and pity rivets.
7. **Numbering drift.** File names, canvas titles and in-file `<title>` all disagree (listed in section 2A), and ux00 says "Five steps" while the canvas order puts "Why" last at 11.
8. **Cross-draft naming:** g01 uses `asha.dhaniverse.eth`; ux00, ux05, ux10 use `sam.tallyport.eth` (docs were renamed Tallyport to Dhaniverse); ux03 prints "TALLYPORT HARBOUR · JOB SLIP". ux08 invents place labels (Arrival Hall, Courtyard Homes, Garden Homes, "the landing") and says so ("a sketch; the real map is drawn from world.json").
9. **Keys:** g01 pocket bar numbered `1` to `6` (and `Game_Layer_Design.md` "Keys 1 to 6"); ux02 relabels slots `TAB`, `P`, `N`, `TICKETS`, `MEAL`. ux03 says `E` Start and `P` Practice free; ux06 says "Hold E" Take it; ux11 says "A card tears ... HOLD E"; ux03 step 1 then says "TEAR IT OFF THE BOARD" with plain `E`.

### Board by board

- **ux00 Journey (first session).** Five steps, dark `#161717`, 104 px badges `radius 34`, ring 3 px, dashed spine. Right idea (three signals: gold diamond, a person who calls you, the island's next line) but: a documentation page with the web kicker/headline pattern; step 1 "sign in with World" before the opening, whereas the founder's opening (memory `opening-order.md`, `Game_Layer_Design.md`) is black, logo, ferry docks under the Tallyport card, name written on the ferry ticket by hand, then menu, with no staged name box ("They reject anything staged or hardcoded, such as 'the name asking input box in a random room'"). Sign-in is not placed in that sequence. No step for eating or energy (quests cost energy, energy comes from food). Step 4 "the box drops ... common to legendary" asserts the lootbox on every quest (founder request) but not how the chest at your door and the weekly strongbox coexist. "6 minutes, the first dollar inside" is unvalidated against the first-hour plan in `Game_Layer_Design.md`.
- **ux01 Audit.** Annotated screenshot of the current build with eight numbered problems. Useful. Gaps: it is an audit of the Godot build not of the earlier boards; it never lists what the boards already specified and the build omitted (the island, hotbar lift, glance), so the reader cannot tell design gap from implementation gap. Its screenshot blob `12a944ca…` is the only evidence; "14 fps, 1.6 million triangles" is not reproducible from the file.
- **ux02 HUD rebuilt on a real frame.** Good: real frame, plates only where words sit on the world, wallet "$4.27 USDC", energy number plus pips, island, gold marker, key hints, name tags, 5-slot pocket. Misses and regressions against B/C/g01:
  - Island: shows the clock pill with a separate second pill for "Paid · The Unload" 40 px below it, not the single morphing pill with lobes splitting out (B Morph, goo filter). No glance card and **no hover behaviour**, which the founder asked for ("it should also act on hover").
  - Mentor plate and `H` key removed (g01 had it; founder kept mentor twice). Item 5 "Names over people" is the only people element.
  - Dropped: energy regen countdown "+1 in 2:41" and TOWN PASS stamp from g01, the Rehearsal-town notice, the minimap "N badge + place pill" kept but 176 px vs 170 vs 188 across boards, hotbar lift/ring/press squash, "NEXT, IF YOU LIKE" tick list (replaced by the gold diamond, a defensible swap, but not stated).
  - The wallet plate says "Held for you $0.04 · stamp your Town Pass" without the stamp image g01 and Game Layer use.
  - The pocket slots shrink to 46 px and put key letters below instead of numbers inside.
  - No `rem` scaling note; the board is fixed 1440x810 px (the founder's "scale to fit" rule is in B/C boards via `rem`).
- **ux03 One quest, start to pay.** Four steps: tear the card off the board (paper, scalloped, rotation -2deg, "Costs 10 energy / Pays fixed $0.04 / Paid by the house pool / Places left today 41", medals G/S/B with times), the run plate with ghost and medal ticks, job slip (GOLD disc, "Tickets +3", lesson line), receipt with "ON CHAIN · 0x9f…c21" stamp and wallet pill. Paper language and receipt stamp match the Game Layer. Misses: no energy-check or refusal state; "Sold out says so and refuses first" is text only; the run plate uses a generic crate counter although the Unload is specced as a crane/cart game; no blast on the first completed quest although Game Layer lists "your first quest done" as a full blast; slip and receipt both appear but the order of events from ux09 (fixed pay lands first, then box) is not drawn here.
- **ux04 Game brand guidelines.** Strong summary (colour jobs, four voices, scale 60·38·24·16·13·11, plate/paper/badge surfaces, parts, 24-grid 2 px icons, motion table, voice). Issues: derived "from the landing and DESIGN.md" but omits the glass button, tag pill, tilted cards and the Figma radii (40/60/80/120), declares gold's job as "proposal" while using it everywhere, rarity colour clash (finding 6), "Money never in Bitroad" is correct (decision of 31 Oct) but no board shows a Bitroad-less money plate differing from the old HUD, motion table says box "0.9 to 3 s" while ux09's timeline runs 4.8 s. "Kicker" voice contradicts its own "no web tropes" stance by using one on every page. It also says "Never coins, points or credits" yet ux03/ux10 use "tickets" (counted, not money, per Game Layer; fine) and "medals".
- **ux05 Sign in with World.** Gate scene blurred; headline "one person, one pass"; benefits (Town Pass, `sam.tallyport.eth`, a wallet made for you), QR card with steps "Open World App / Scan this code / The gate opens", "[QR from IDKit goes here]", guest option `G`. Problems: the AI web trope (finding 3); an HTML-style modal on a blurred photo rather than World ID in the game's own gate prop (`Game_Layer_Design.md` "World ID: Screen, IDKit's own window, over the desk scene"; the founder's rule that screens live on real objects); no logo, no title menu, no ferry; "Walk in as a guest" is a new product decision (Technical Plan: nobody has to deposit; Town Pass gates golden drops) that is not marked as a question for the founder; a placeholder QR (acceptable) but the board never shows the `Town Pass` stamp moment or its blast.
- **ux06 The quest board.** The strongest board: tabs Today/Sponsored/Errands/Mystery/Done, six white cards with badge, who pays, energy, USDC chip, places left, box rarity, a detail drawer (steps, FIXED PAY $1.00 "your cargo back + $0.50", rare box odds bar 55/30/12/3, medal times, `Hold E Take it, 30 energy`, `P Practise free`). Matches h03 quest copy and the plan's sponsored quests. Gaps: cards use the landing light style inside a dark full screen, mixing the two surfaces; no glass button; the odds bar's rarity colours reuse money/people/gold (finding 6); "Market Rush" is shown with "pot $12.40" and "COMMON BOX ON EVERY RUN" while Game Layer says Rush pays top-10 USDC from a free contest and a box per run is new; "pot $12.40" and "COMMON BOX" together are two random/ranked USDC streams with no budget arithmetic against the 4%/day house pool; the "Hold E" semantics conflict with ux03. Quest names are consistent with h03.
- **ux07 Markers.** One gold diamond, badges for the rest, edge arrows with distances, route on the minimap, island line "Carry the spice to the merchant · step 3 of 3 · 85 m", rules "within 8 m it folds into the green key hint". Matches ux11's fold. Gaps: minimap 220 px (a fifth size), no "ping every 2 s" and place-name roll from B HudMotion, `M` opens the map but no Bitroad N badge detail beyond a circle, and the island's "next line" duplicates the shape of the lobe without the morph.
- **ux08 Town map.** Left dark panel 360 px with the quest list and `E Track`, `F Show on map`, `M Close`; sketch map. Fine as a proposal and honest about being a sketch. Misses: no legend for the "box" marker, no fast-travel (not wanted), and uses the dark plate at 30 radius (a fifth plate radius: 20, 26, 30, 32).
- **ux09 The box: drop, open, paid (live).** 7 s loop: thud, hold E 0.8 s with ring, lid pops, rarity light, prize rises, flies to wallet, balance rolls; tier table; pity as ten rivets "7 of 10"; three money rules (fixed pay first, sponsor and surprise pool pays, never sold). Strengths: server draws before the box lands, any key skips, rivets for pity (from g02). Problems: (a) it replaces g02's physical wood/brass/gold chest with a generic blue box and drops the odds plate on the chest's side, the weekly strongbox and the streak growth that `Game_Layer_Design.md` specifies; (b) it makes every quest pay a random bonus up to $2.00 while Game Layer rule 5 says no quest reward is random, rule 2 says skill never pays USDC, and the Technical Plan funds only 20% of 4% a day into chests: no budget table; the draft says "proposals until set in rules.toml" but the Indian-law "stake" risk in the plan is not mentioned; (c) legendary gets the full blast only 3% of the time, and the founder's "milestone was so dopamine giving earlier... the blast" is reduced to one rarity; (d) no reference to predict.fun, which the founder named as the model, appears in the board (not researched or cited); (e) timeline runs 4.8 s versus the 3 s opening in g02 and ux04's own motion table; (f) the stage is a navy radial gradient not a real frame; (g) tier colours conflict (finding 6); (h) pity differs from the Technical Plan (Epic on 10th box vs golden drop on 10th chest).
- **ux10 The wallet.** Phone held at an angle (400 x 804, ring 3, radius 52) with Feed/Quests/Wallet/Town tabs, balance card, Held for you / At the chain, Send / Withdraw / Add, receipts with tx links, tickets and meals count; right side explains Balance, Held, At the chain, Receipts, Withdraw ("gas paid by the town. FOOD never leaves the game"), Tickets and meals. Matches the Wallet and Food design and Privy decision. Misses: not the landing's bank card (d03), no Town Pass state, "Send" and "Add" are unspecified product features (Add implies deposit; plan says nobody has to deposit), the gradient balance card is a new surface, the phone bezel is a sixth radius. Still on a blurred full-screen background.
- **ux11 Motion.** Six live loops: island lobe (0.5 s out), digit roll 400 ms with "+0.04" rising, key hint pop 150 ms and key sink 2 px, card tear 1.2 s hold E, marker folds into the key within 8 m, orange event toast 5 s timer with low-energy pip breathing 1.6 s. Good set that restates B's timings. Misses: the island lobe here is a width tween on a separate plate (no goo split); sun cycle, map ping, hotbar lift, goals tick, split-flap price are not carried; no hover glance; no glass-button press; no milestone blast although the founder asked to keep it; its rule "Nothing moves unless something happened" matches Game Layer rule 10, and banning shake and pulse for everyday UI matches the founder's 30 Oct note.

### What to carry forward (earlier work to reuse, not re-invent)

Dark cream-ringed plate; key cap with `#9d9477` lip; green E pill with tail; the single morphing island with staged 0/90/180/310/500 ms split, goo filter, queue dots, glance on hover or Alt, sun dial; digit roll and rising gain; pips filling 70 ms apart and the 1.6 s low-energy breath; map ping and place-name roll; hotbar lift and ring draw; orange toast with timer; tear-off paper and "ON CHAIN" stamp; milestone blast for the Town Pass, first quest, strongbox, draw; the title opening and menu roll; settings tabs with hold-to-compare; g02 chest (rivets, odds plate, golden drop blast); the landing's glass button on every clickable web control and every full-screen menu button; the landing's d03 bank card for the wallet; the landing's tag pill and tilted card language for the quest board and any web page; light landing style stays on the web (and full-screen menus where badges are allowed), the HUD stays dark.
