# UI audit: the game against the Game UX boards

Rule (founder, 2026-11-07): anything on screen that no board or artifact shows is slop and goes. A new element is designed on the canvas first, then built 1:1. Boards are on the main canvas, Game UX page: https://claude.ai/artifact/NXZoisr29vwkuHyNoJkP6N (local copies in the scratchpad's `main/project/ux*.dc.html`).

Status per element: **ok** (matches its board) · **slop** (remove) · **missing** (build to the board) · **wrong** (rebuild to the board).

## HUD in town: ux02 (and g01)
| Element | Board | Today | Status |
|---|---|---|---|
| You plate | face ring, name, energy number with 10 pips, one line | face, name, 5 pips, "Energy 100" and "Free thali ready" on separate lines | wrong: 10 pips, the number beside them |
| Wallet plate | blue $ disc, amount, "USDC", one line about money held for you | adds "REHEARSAL", "Town Pass", "1 ticket · streak 1 of 5 days" and "Your chest is ready, at your door" | slop: everything but the amount and the held line |
| Edge shading | none | dark gradient round the screen | slop |
| Island | clock, day and sun; lobes grow out of it; queue dots; glance on hover | as built | ok |
| Island Next line | "Next · place · N m" | built | ok |
| Minimap | round, roads, water and buildings in the town's colours, N badge, gold diamond and route, the place name inside at the bottom | green blocks; the place name outside, under it | wrong |
| Mentor plate | under the minimap: a serif italic line and "H Ask the mentor", only after something real | only an island lobe | missing |
| Pocket bar | 5 slots numbered 1–5 with names under them: Wallet, Quests, Feed, Town, Mentor | odd icons, names on hover only | wrong |
| Key list | none | removed | ok |
| Key hints | green with a tail, on the nearest thing | as built | ok |
| Name tags | magenta, name plus what they offer or a title | dark plates | wrong |

## Board in focus: ux06
| Element | Board | Today | Status |
|---|---|---|---|
| Cards | paper on the cork; badge, lowercase title, who pays, places left, energy, pay in blue, the crate's tier | as built, without the tier mark | missing: tier mark |
| Island bar | title, energy, ← →, hold-E ring, Esc | as built | ok |
| Other screens over it | none | the phone could open over it | fixed: one screen at a time (Screens gate) |
| Sponsor info | not on any board | an invented dark panel, now removed | design first (see Uniswap below) |

## Phone and wallet: ux10
| Element | Board | Today | Status |
|---|---|---|---|
| Tabs | Feed, Quests, Wallet, Town | adds "Me" | slop |
| Bank card, balance, transactions | the landing's bank card | as built | ok |
| Deposit and Withdraw | on the board: Withdraw and Receipts pills | Deposit and Withdraw, both working | board to update with Deposit |
| Feed reactions (Clap, Ha, Wow, Aw) | not on a board | there | slop, until designed |

## Uniswap: the Spice Run, ux12
| Element | Board | Today | Status |
|---|---|---|---|
| The exchange | an in-world quote board over the kiosk, a brass scale, the island bar with "hold E, pull the lever" and "Q new quote", "AT THE CHAIN" stamp | a full-screen paper sheet | wrong: rebuild in the world |
| What Uniswap is | not on a board yet | removed | design first: the founder wants the logo and a short description |
| IOU slip, delivery by ENS name | ux12 steps 2 and 4 | text only | missing |

## Missing screens
- **The gangway gate and World ID (ux05):** the ticket held in hands, the IDKit panel, "later", the clip and the stamp.
- **The quest crate (ux09):** a crate drops after a quest, hold E, wood, brass or gold, the golden drop flying to the wallet. Needs the server.
- **Waypoints (ux07):** badges over quest givers, edge arrows with distances.
- **The town map on M (ux08).**
- **Job slip and receipt (ux03).**

## Built without a board (needs one, or goes)
- **Pause menu:** in the Settings style; the founder asked for it. Put a board on the canvas.
- **Access settings section:** inside the designed Settings layout; keep.
- **Food menu and chest result sheet:** from the earlier Brand Directions era, not on the Game UX page; to redesign.

## Order of work
1. HUD to ux02 exactly: plates, minimap, mentor plate, pocket bar, name tags; slop removed.
2. Waypoints and minimap to ux07.
3. The Uniswap run to ux12: the exchange in the world, plus a designed "what is Uniswap" (canvas first).
4. The crate to ux09 (server and client).
5. The gangway gate to ux05.
6. The map to ux08, then the slip and receipt to ux03.
