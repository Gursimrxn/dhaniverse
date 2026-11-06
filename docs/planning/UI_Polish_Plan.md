# UI and game layer polish: the checklist

The founder's brief, 2026-11-07: fix all of the UI, the game layer, the title screen, Esc, accessibility and the minimap. Add a proper loot event and waypoints from the Game UX boards. Build every screen the smart wallet and the on-chain parts need. It must be smooth and very polished. Work in the Godot desktop build first; web speed comes last.

Sources: the Game UX page of the main canvas (`ux00`–`ux11`), `Artifacts_Digest.md` (exact visual language), `Code_Map.md` (where things live).
Verify every item with `game/dev/ui_tour.gd` captures; then one professional commit per finished feature.

## Order

1. [ ] **Esc opens a pause menu**, not settings: Resume, Map, Settings, Controls, Quit to title, Quit game (desktop only). The game holds behind it, dimmed; Esc again resumes.
2. [ ] **Accessibility in Settings**: text size, reduce motion, hold-or-press for hold actions, subtitles size, mouse sensitivity, invert Y, high-contrast markers.
3. [ ] **Minimap rebuilt**:
   - a real top-down render of the town baked once at load, styled;
   - quest badges, the tracked route, edge arrows, the place pill;
   - zoom.
4. [ ] **The full map on M**: the same render, larger, with quest pins and the tracked quest.
5. [ ] **Waypoints in the world**: badges over quest givers, edge arrows off-screen, the gold diamond only for the tracked quest (ux07).
6. [ ] **A cleaner HUD**:
   - the You plate (face ring, name, energy number and pips);
   - the wallet plate (the dollar amount plus one line);
   - no standing key list; pocket labels; magenta name tags.
7. [ ] **The quest crate event** (server and client): a crate drops when a quest ends; hold E; the reveal under 3 s; the prize flies to the wallet plate. Lucky crates turn up around town each day as waypoints. Wood, brass and gold. Golden drops come from the surprise bucket.
8. [ ] **The phone, rebuilt**: the wallet as the landing's bank card, receipts with transaction links, withdraw, the Town Pass, your ENS name, quests and the town.
9. [ ] **On-chain screens**:
   - the meal purchase confirm;
   - the swap quote (Spice Run);
   - pending and confirmed states;
   - the Town Pass and World ID;
   - the ENS name;
   - errors in plain words.
10. [ ] **Food, chest and board sheets**: in the world, not dark web panels.
11. [ ] **The title screen and the ferry ticket held in hands**.
12. [ ] **Players never see "Tallyport"**: the Tally paper, the letter, the title card, quest text. The ENS parent stays configurable until a name is registered.
13. [ ] **Sepolia launcher**: run the chain server (`tallyport --chain sepolia`) from `.env.sepolia` with the publisher live on Arkiv, and point the exe at it.

## Notes

- ENS: neither `tallyport.eth` nor `dhaniverse.eth` is registered on Sepolia (registry owner is zero, checked 2026-11-07). `contracts/deployments/sepolia.json` names `tallyport.eth` as the parent, so name registration needs the founder's call.
- CI: the contracts workflow runs `forge lint -D warnings src` on Foundry v1.8.1.
