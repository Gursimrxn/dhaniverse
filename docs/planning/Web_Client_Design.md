> **Shelved.** The three.js client this describes was dropped; the game ships as the Godot web export, framed at /play. The sections on real money (nothing in the browser is trusted) and on cutscenes still apply.

# Dhaniverse in the browser: the web client

Draft for the founder's approval. Nothing here is built yet.

## Why

The game has to live on the website and run fast in any browser, with a tiny download. The founder's targets are
the whole game at about 1 MB and "1000 fps". Everything that comes after this (the onboarding, the game layer from
the technical plan, chests and streaks, quests with real skill and thrill, the UI pass) gets built on this client,
so it has to be small and fast from the first step instead of being slimmed down at the end.

## What we measured

| Fact | Number |
|---|---|
| Godot client on disk | 337 MB |
| All glTF models in the repo | 182 files, 292 MB, 3.4 million triangles, 0.8 MB of images |
| Models the default town actually loads | 88 files, 74 MB, 1.25 million triangles (buildings alone 987,000) |
| Biggest loaded model | `game/assets/town/dv22_apartments.glb`: 161,216 triangles, 7.8 MB |
| The player character (`cozy_boy.glb`) | 69,096 triangles and 0.8 MB of textures, for one person |
| Other loaded data | 12 MB of WAV, a 660 KB water normal map, a 48 KB `world.json`, a 40 KB flagstone image |
| How the sounds were made | rendered offline by `tools/make_audio.js` from oscillators and noise |
| The three.js valley the Godot world was ported from (`reference/futuristic-retro-nature` in the old repo) | 212 KB gzipped for the whole build, three.js and React included, with no asset files |
| Godot's web engine alone | about 42 MB uncompressed and 8.7 MB zipped by default; about 2.7 MB brotli after stripping a custom build ([measured by popcar](https://popcar.bearblog.dev/how-to-minify-godots-build-size/)), before any game content |
| The native Godot build on the founder's laptop | about 40 to 50 fps: 14 to 17 ms of GPU time looking from the stall, 1.47 million triangles drawn (`docs/planning/Mumbai_Game_Plan.md` in the old repo) |

Two conclusions:

1. **The weight is triangles, not textures.** KTX2 is the right format for textures, but the game has almost none,
   so it would not move the number. For geometry the equivalent is simplification, quantisation and meshopt
   compression.
2. **Godot cannot reach 1 MB.** Even a stripped engine is bigger than the whole budget.

## Decision: a Rust core, drawn by three.js, in the browser

The client is rebuilt for the browser in three layers:

- **Rust, compiled to WebAssembly, is the game's core.** The server links the same crates. It holds the town's
  layout and generation (`worldgen`), physics (Rapier, a Rust physics engine), and the moment-to-moment game logic
  (`game-core`: movement, plus the rules and scoring of the skill games). The protocol's message types are defined
  once, in Rust.
- **three.js draws it** (WebGL2): the scene, the shaders, skinned animation, sound and input, in TypeScript.
- **React in Next.js 16 is the UI around it:** the HUD, the menus, the wallet, World ID and ENS.

The Godot client stays in the repo unchanged, as the visual reference, until the founder signs off that the browser
version matches it. Then it is retired.

Why:

- **Rust where it pays.** Skill games pay real USDC, so the server has to be able to check a result before paying.
  With the same `game-core` on both sides, the server replays a run's inputs and gets the same score: the referee
  the technical plan asks for. Physics comes from Rapier instead of hand-written collision. Message types live in
  Rust, and the TypeScript types are generated from them, so the client and the server can't drift apart.

- **Size.** The three.js valley is 212 KB gzipped. Godot's engine alone is over 1 MB.
- **Speed.** Hand-batched three.js draws the town in a few dozen draw calls and loads in about a second. Godot's
  web build runs its compatibility renderer on one thread, with engine overhead we can't remove.
- **It fits the site and the technical plan.** Next.js pages, a React HUD, the ERC-4337 smart wallet SDKs, World ID
  (IDKit) and ENS (viem) are all JavaScript. In Godot each needs a JavaScript bridge; today the Town Pass even opens
  in a separate browser window.
- **The look started on the web.** The valley's shaders cite the three.js app they came from, its textures are
  byte-for-byte exports of that app's `textures.ts`, and the trees are a port of just-a-simple-tree (JavaScript,
  MIT). Going back is a known path.
- **The rules stay put.** The Rust server already holds every rule and the client only shows them, so this rebuilds
  the presentation, not the game logic.
- **No Godot-only features stand in the way.** The default world uses the compatibility renderer (WebGL2-class), with
  no GPU particles, global illumination, compute shaders or threads.

What Godot gave us, and what takes its place. Nothing an engine provides is written from scratch:

| Godot gave us | In the browser | Language |
|---|---|---|
| Rendering, materials, the scene tree | three.js | TypeScript, shaders in GLSL |
| Physics, CharacterBody3D with step-up, shape casts | Rapier: rigid bodies, sensors, ray and shape casts, a kinematic character controller with step-up, slopes and ground snapping | Rust |
| Skeletal animation and blending | three.js `AnimationMixer`; the foot planting and arm aim are ported | TypeScript |
| Audio buses and 3D sound | Web Audio, through three.js's positional audio | TypeScript |
| UI (Control nodes) | React and CSS | TypeScript |
| Tweens and cutscene tracks | GSAP, which the website already uses | TypeScript |
| Particles | instanced shader particles | GLSL |
| Import pipeline and generated LODs | glTF Transform and meshoptimizer | TypeScript (a build tool) |
| Navigation for the townspeople | a path graph generated by `worldgen` | Rust |
| The web export | not needed: it is already the web | |
| The editor | Blender for the town (as now), data files, and a debug panel in the page | |

What we write ourselves is what we already wrote ourselves in Godot: the shaders, the world, the gameplay and the UI.

This replaces the Godot web export in `docs/specs/frontend/3D_Frontend_Production.md`: a single-threaded Godot
build with a 24 MiB cold download and 1280×720 at 30 fps as its targets. What carries over from that spec: the
founder's laptop as the measured device, WebGL context-loss handling (show a recover screen, reload), cursor capture
only after a click with a clear way out, wallet SDKs living in the page around the game, and no cross-origin
isolation.

Considered and dropped:

- *Keep Godot and optimise it:* its engine is bigger than the budget, and the wallet, World ID and ENS stay awkward.
- *Godot with Rust (godot-rust):* Godot's engine size stays, and Rust extensions on the web are experimental.
- *Bevy, the all-Rust engine:* the most Rust possible, but a recent 3D Bevy web build is about 22 MB raw and about
  5 MB brotli ([codeberg.org/jhartma/game](https://codeberg.org/jhartma/game)), five times the budget before any art.
  It runs single-threaded in the browser with a heavy renderer, the UI, wallet, World ID and ENS would still be
  JavaScript around it, and its build folders run to several GB on a disk with about 3 GB free.
- *A custom wgpu renderer in Rust:* that means writing a rendering engine, and three.js already is one.
- *React Three Fiber:* it would let React draw the 3D scene too. The world stays in plain three.js for speed, with
  React for the UI around it.
- *Babylon.js or PlayCanvas:* bigger runtimes, and the look was never made in them.
- *three.js's WebGPU renderer:* a bigger bundle and fewer devices today. WebGL2 runs almost everywhere and is what
  the look was made in. Revisit only if a measurement shows WebGL2 holding something back, such as grass culling
  on the GPU.

## Goals

### Size

Measured as bytes over the network, brotli compressed.

- **First playable at most 1 MB.** The page, the engine, the town on screen and the player walking. A CI check
  fails any change that pushes it over.
- **Everything else streams in** while the player walks, nearest first.
- **The whole game's total** is measured on every build and reported next to the 1 MB line, and the work pushes it
  under 1 MB as well. The first real reading comes from the bank and café prototype (see *Assets*).

### Speed

- **What "1000 fps" means here.** Browsers draw at the screen's refresh rate (60, 120 or 144 times a second), so
  nobody sees 1000 in a normal tab. What 1000 fps really buys is headroom: the cheaper each frame is, the steadier
  the game stays on slow phones and busy laptops. So speed is measured as milliseconds per frame, in a test browser
  with the frame cap removed.
- **On the founder's laptop** (i7-1255U, Intel UHD Graphics, Edge or Chrome, 1920×1080): the floor is never under
  60 fps while walking anywhere in town, and no frame over 25 ms after loading. The aim is an uncapped average of
  200 fps (5 ms a frame), against about 40 to 50 fps for the native Godot build today.
- **Playable within 2 seconds** of opening `/play` on a 20 Mbps connection with an empty cache.
- **No automatic resolution drops** (the founder's rule). The canvas renders at the screen's resolution, capped at
  2× pixel density.

### Look

The same town with the same look, judged side by side with the Godot build at fixed camera spots. The values below
are what the default build runs today.

- **Light.** The four looks (dawn, day, evening, night), blended over 2.5 s, with T cycling them. Sky lighting
  projected to spherical harmonics. Fog and cloud shadows inside the materials. The five season leaf looks (Y, or a
  server shock).
- **The grade pass.** Bloom, 12-step light rays, three.js ACES and sRGB, the colour grade, vignette and sharpening
  ("optimise without changing the look"; no animated grain).
- **Trees.** The 22 generated shapes (oak, young oak, pine, cypress, bush), with leaf atlases painted in code, their
  sway, flutter, seasons and ages, as just-a-simple-tree grows them.
- **Grass and flowers.** The newer grass: three rings that follow the camera (9, 20 and 55 m), blades built in the
  vertex shader, parting where characters walk. The 260 flower drifts.
- **Ground and water.** The terrain from `world/valley/world.json` and its 2 m grid, levelled under the buildings,
  with the flagstone paths. The river's four reaches with refraction and reflection, and the waterfall.
- **Buildings and props.** The town's buildings as exported from the Blender town file, and the 39 kinds of prop
  in 390 places.
- **Characters.** The player's `cozy_boy` with its Idle, Walk, Run and Victory clips, foot planting and arm aim. The
  townspeople as recoloured `folk.glb` figures.
- **Movement and camera.** Walk at 3.4 m/s, sprint ×1.65, a 0.5 m step-up. C cycles top-down (7 to 30 m, FOV 38),
  third person (2.2 to 9 m, FOV 62) and first person (FOV 72). Z and X rotate, the wheel zooms, springs smooth the
  follow, and indoors forces third person.
- **Sound.** The ambience by place, the dawn, day and night music, footsteps by surface and the short effects.

### On the website

A Next.js app with the game at `/play`. No other page downloads any of the game.

### The technical plan, respected

The client only shows; the Rust server is the referee. The client never works out a price, an amount or a reward
(`server/PROTOCOL.md`). USDC is the only money. The wallet, World ID, ENS and Arkiv arrive with the game layer, on
this client.

## What comes next, on top of this

In the founder's order, each built on this client: the onboarding and the opening; the game layer from the
technical plan (energy, meals at live prices, the Bounty Board, the Spice Run, chests, streaks, the rescue meal);
chest and streak systems with real dopamine; quests with skill and thrill, and new mechanics; the UI and UX pass;
the live deploy on dhaniverse.com with the server hosted.

The design, the brand, the game layer and the game UX all have to be outstanding, and the Figma is their reference
(`D:\m\Dhaniverse.fig`, exported to `D:\code\Godot\dhaniverse-v2\figma`): the landing page, the HUD, the chests and
every other UI element. That work gets its own design, with the founder, on top of this client. This client is
built so it can carry it: React and CSS for the UI with the Figma's fonts and colours, GSAP and shader particles for
the big moments, and game-core for skill mechanics the server can check.

The Godot build already has a game layer (the Bounty Board, Spice Run, Market Rush stall, chests, the Town Pass
desk, the sign painter, the price board, Gran's letter, the phone: about 6,600 lines of UI). It is not ported as it
stands, because the founder wants the quests redesigned to feel like real games. Its server side (protocol v3) stays,
and the new screens use it.

This piece starts the player straight in the town with a click to play. The opening (black, the logo, the ferry
docking with the Tallyport card, the menu, the name on the ferry ticket, the harbourmaster, Gran's letter) is rebuilt
together with the new onboarding, keeping that order.

## Anti-goals

- A worse look to hit the numbers.
- Feeling like a website with a 3D background.
- Stutters while walking, or long loading screens.
- Downloading anything the current screen doesn't need.

## How it is built

### Repository layout

```
apps/web/                 Next.js 16 app: /play now; the landing page and today's web/ pages move in later
packages/engine/          the game client: TypeScript on three.js, no framework; start(canvas, options) returns a handle
server/crates/worldgen/   Rust: the town layout and everything generated from it
server/crates/game-core/  Rust: movement, physics (Rapier) and the skill games' rules; deterministic
server/crates/web/        Rust: the browser build, worldgen and game-core behind one small JavaScript API
                          (worldgen and game-core are also linked natively by the server)
tools/assets/             the asset pipeline: source .glb in, compressed .glb and a manifest out
game/                     the Godot client, frozen as the reference
```

A pnpm workspace holds `apps/web`, `packages/engine` and `tools/assets`. `services/publisher` keeps its own npm
setup.

### In the browser

- **Main thread.** `/play` loads the engine with `next/dynamic` (no server rendering) and hands it a canvas. One
  `requestAnimationFrame` loop. The Rust core runs on a fixed 60 Hz tick and drawing interpolates between ticks, so
  speed never depends on frame rate. The React HUD reads a small store when something changes (`useSyncExternalStore`), never every frame.
- **A worker.** `worldgen.wasm` runs in a Web Worker: terrain, paths, the placement of grass, flowers, trees and
  rocks, tree meshes, and collision. Results come back as typed arrays, transferred without copying. The meshopt
  decoder runs there too. Today Godot builds the whole valley on one thread while the screen is black; this moves
  that work off the main thread.
- **Drawing (WebGL2).** Shared materials ported from the valley shaders, with their roughly 115 global values in one
  uniform block. Instancing for everything repeated (trees by species and age, rocks, flowers, props). Static
  geometry merged per chunk and material. Chunk and frustum culling. Levels of detail from the asset pipeline, with
  impostors for far trees. Ambient occlusion baked into the buildings' vertex colours. One post pass for the grade,
  with bloom on a half-resolution chain and light rays at quarter resolution. Shaders compile during loading
  (`compileAsync`), so the first steps don't stutter.
- **Shadows.** Today high quality draws a 4096 sun shadow map every frame and low quality uses blob shadows. Here the
  sun's shadow of the buildings, trees and ground is drawn once per lighting look into a cached shadow map and reused
  every frame, since none of them move; characters keep blob shadows. Tree shadows therefore hold still while the
  leaves sway; the parity sheet decides whether that shows.
- **Water.** Today each water pixel traces a 28-step screen-space reflection. Here the reflection is rebuilt cheaper,
  at reduced resolution, and judged on the parity sheet.
- **Colour.** The grade pass applies ACES and the sRGB conversion itself, as it does in Godot, so three.js's own
  output conversion stays off and nothing is encoded twice.
- **Memory.** No allocations inside the frame loop, because garbage-collection pauses are stutters. Everything is
  disposed when the player leaves `/play`.

### What runs in Rust

- **worldgen.** Heavy, deterministic generation off the main thread, with SIMD. The server links the same crate, so
  the server and the browser agree on the map: spawn points, doors, walkable ground and the townspeople's paths.
  The server can check positions against it later.
- **Physics.** Rapier, linked into the same WebAssembly module with only the features we use. Its kinematic
  character controller gives the 0.5 m step-up, slopes, sliding along walls and ground snapping. Sensors handle
  doors and triggers, and ray casts keep the camera out of walls.
- **game-core.** Deterministic, on a fixed 60 Hz tick. The browser calls `step(input)` once a tick, and the core
  writes positions and animation states into a buffer in WebAssembly memory that three.js reads directly. That is
  one crossing between JavaScript and WebAssembly per tick, never one per object. The skill games' rules live here,
  so the server can replay a run's inputs to check its score before paying. Anything physical in those games uses
  Rapier's cross-platform determinism mode, so the native build and the WebAssembly build agree to the bit.
- **Protocol types.** Defined in the server's Rust; TypeScript types are generated from them with ts-rs at build
  time, so nothing extra downloads. JSON stays the wire format (protocol v3).
- **No prices, amounts or rewards in the browser.** The server works those out. game-core only decides what the
  player did (where they went, what they hit, their score), and the server checks it.
- **At most 300 KB of WebAssembly, brotli, Rapier included,** measured in the first step. No serde or string
  formatting in the browser build, a size-optimised release profile, and wasm-opt. If Rapier doesn't fit, its
  features are trimmed further. The last resort is a small capsule controller on parry, Rapier's collision library.

### Assets

- **Buildings.** Weld, simplify with meshoptimizer to an error limit per building, generate levels of detail,
  quantise positions, normals and colours, bake ambient occlusion into vertex colours, merge by material,
  meshopt-compress. The bank and the Common Table café go first and are shown side by side with Godot before the
  rest are run.
- **Props.** The same pipeline; their existing near and far models become the levels of detail.
- **Characters.** `cozy_boy` simplified from 69,000 triangles; its four clips resampled, quantised and compressed.
  The `folk` figures share one skeleton and one set of clips.
- **Textures.** The leaf atlases, the water normal map and the noise textures are generated in code (the water
  normal map is already an export of a procedural texture). The character's few textures ship as WebP, which the
  browser decodes for free. KTX2 (UASTC or ETC1S) is for texture art added later, and the Basis transcoder (about
  180 KB) loads only once something needs it.
- **Audio.** The sounds from `tools/make_audio.js` are generated in the browser while loading
  (`OfflineAudioContext`), so they cost no download.
- **Fonts.** WOFF2, subset to the characters used.
- **Output.** Content-hashed files under `apps/web/public/game/`, cached forever, with a manifest of sizes. They are
  small enough to commit, so a deploy doesn't need Git LFS. The pipeline regenerates them from the sources in
  `game/assets`.

### The network client

The browser speaks protocol v3 to the Rust server over WebSocket, as `client/town_client.gd` does today: `hello`,
`command` with its `ref` (resent with the same ref after a reconnect), `move` at 5 Hz, and the server's snapshot,
event, you, city, time, presence, left and error messages, into the store the HUD reads. Other players appear and
walk around. With no server the town still runs, alone. The 25 protocol and state tests in `game/tests` are ported to
the new client. No game screens come with it; those are the next piece.

### Next.js

- Next 16, React 19, TypeScript in strict mode, Turbopack.
- Game files are served as static files with brotli and immutable caching. WebAssembly loads with
  `instantiateStreaming`.
- A Content Security Policy that allows `'wasm-unsafe-eval'`. No cross-origin isolation headers, because nothing
  uses WebAssembly threads, so any host works.

### Running it

Everything runs locally first: a local Next.js server (and the local Rust server for the network client), opened in
a browser on the founder's laptop. Nothing is pushed or deployed until the founder says the local build is right.
The founder hosts dhaniverse.com, and how the game goes live there is decided then.

## Checks

- **CI on every push.** Typecheck and lint. Unit tests (Vitest) for the camera, movement, collision queries, loaders
  and the network client. Rust tests for worldgen (the same seed gives the same bytes) and for game-core (the same
  inputs give the same state in the native build and the WebAssembly build, and collision holds). The asset
  pipeline reproduces the committed outputs. The size check. A Playwright run in Chromium that opens `/play`, sees a
  canvas that isn't blank, walks, and sees no console errors.
- **A local speed harness on the founder's laptop.** Edge with the frame cap removed, a fixed walk and fly-through of
  the town, reporting average and worst frame times, draw calls and triangles, saved as JSON for each run.
- **A parity sheet.** The same camera spots captured in Godot (its existing `--snap`) and in the browser, on one sheet
  for sign-off, in each of the four lighting looks.
- **Disk.** D: has about 3.2 GB free and C: about 0.3 GB, so every cache lives on D: (the pnpm store, Cargo's
  temporary files), and Playwright drives the installed Edge instead of downloading browsers.

## Order of work

1. **Skeleton.** The workspace, the Next.js app with `/play`, the engine with an empty scene, the Rust core built to
   WebAssembly with Rapier linked (so its size is known from the start), the size check and CI. Something runs on a
   page from the first step.
2. **worldgen in Rust**, as WebAssembly in a worker: the valley's layout from `world.json`, the terrain, the
   levelled ground, paths, the river and the waterfall, drawn in the browser.
3. **Foliage:** grass, flowers, trees and the river stones.
4. **Buildings and props through the pipeline:** the bank and café prototype for sign-off, then the rest.
5. **The player:** `cozy_boy`, clips at gait speed, foot planting, the camera rig, and movement through game-core
   and Rapier's character controller.
6. **The look:** the four lighting looks, the grade, bloom, light rays, the cached shadow, seasons, sound.
7. **The townspeople and the network client:** the `folk` figures, other players, offline mode.
8. **Speed to budget and the parity sheet,** on the local build.

## Character feel

Not parity: the founder finds today's character laggy. The browser version has to feel better than Godot's.

- Animation is sampled every rendered frame, and positions are interpolated between the 60 Hz ticks. Nothing is
  stepped by hand.
- Locomotion blends idle, walk and run by the real ground speed, with the stride matched to it so the feet don't
  slide. Crossfades take 0.1 to 0.2 s.
- Movement has acceleration and deceleration curves. Turning eases toward the move direction, with a slight lean.
- Feet stay planted on steps and slopes (two-bone IK), and the arm aim is kept.
- The camera follows on critically damped springs. Input shows as motion within one frame.
- A richer clip set: start, stop, turn, step up, interact and celebrate, taken from the Quaternius pack (CC0)
  wherever `cozy_boy` has no clip, and retargeted if the bones differ.
- The founder signs off the feel on the local build.

## Animations and cutscenes

- **Blender is the editor.** The town already comes from Blender. Cutscenes (camera moves, the ferry, characters,
  objects) are animated on its timeline and exported as glTF animation clips. A small JSON file next to each adds
  the markers: sounds, subtitles, UI beats, letterbox in and out.
- **three.js plays them.** `AnimationMixer` drives characters, cameras and objects, with blending, crossfades,
  additive layers and per-bone masks. GSAP times the UI around them. A `CutscenePlayer` in the engine runs one
  sequence: its clips, its markers, and a skip.
- **Rust decides gameplay animation states.** game-core decides which clip plays and the blend weights,
  deterministically; three.js only samples the poses.
- **Theatre.js was considered and dropped.** Its editor is AGPL, it hasn't been updated since May 2024, and Blender
  does the same job with a tool the team already uses.

## Real money: nothing in the browser is trusted

Any client, whether a browser, a Godot build or a phone app, can be read and changed by its user: developer tools,
edited WebAssembly memory, forged messages, bots. So the browser holds nothing that decides money, and tampering
with it gains nothing. The client technology doesn't change this; the server design does.

1. **The server decides every amount:** prices, rewards, payouts and chest contents. That is already the protocol's
   rule. USDC leaves only as a server-signed EIP-712 voucher, checked on chain against the per-human daily cap and
   the source's budget (the technical plan).
2. **Skill games run on the server too.** The browser streams its inputs each tick. The server runs the same Rust
   game-core in real time, and its result is the score. The browser's copy only predicts, so the game feels
   instant, and is corrected when it disagrees. Speed hacks fail against the server's clock, an edited score means
   nothing, and a replayed run fails because inputs are bound to a server-issued session and seed.
3. **Randomness comes from the server.** Each run's seed is committed before the run (its hash is sent first, the seed
   after), so nobody can precompute a run. Chest outcomes are drawn by the server from the house pool with the pity
   rule. The browser only plays the reveal of a result that is already decided, so skipping or editing the
   animation changes nothing.
4. **One human, one account.** World ID before any USDC claim, as the technical plan says, and per-human caps, so
   farming with many accounts pays nothing.
5. **Bots.** The server checks each run's inputs for inhuman patterns: reaction times, perfect consistency,
   impossible rates. Suspicious runs are held for review instead of paid. The daily caps bound what a bot could earn
   anyway.
6. **Positions.** The server checks movement against the same worldgen map (speed, walls), so teleporting to a quest
   spot doesn't work.
7. **Sessions.** Sign-in by wallet signature and short-lived session tokens. Every command carries its `ref` (as now),
   so a replayed command is ignored. No secrets in the browser. Debug commands exist only on rehearsal servers,
   never in production.
8. **Contracts and keys** as in the technical plan: separate keys per role, on-chain daily caps, a multisig admin,
   and a paymaster limited to our contracts, with a limit per user.

Points 2, 3 and 5 are built with the skill games in the next piece. This piece makes game-core deterministic and tests
it in both builds, so it is ready for them.

## Phones and other platforms

This piece targets desktop browsers with keyboard and mouse. Phones come after, in one of three ways: the same web
client with touch controls and quality tiers; a native shell around it; or a Godot build that links the same Rust
crates through godot-rust. The Rust core is what makes the last option cheap.

## Calls made in this design (check these)

- The 1 MB cap covers the first playable; the whole game's total is tracked and pushed down. If the total needs it,
  the seven rebuilt buildings, which already come from recipe code in the old repo (`tools/blender/build_concept_town.py`
  on `concept_kit.py`), can be generated in Rust at runtime instead of shipped as meshes.
- Coarse first, sharp soon: the loader brings the lowest detail of everything in view first, then sharpens, nearest
  first. The size check measures up to the moment the game is playable. Standing still, everything is at full detail.
- Until the onboarding exists, a player's name comes from the URL (`?player=`, like Godot's `--player=`), with no
  server change. Without one the town runs offline.
- Phones are out of this piece.

- A Rust core (worldgen, Rapier, game-core) with three.js drawing it, rather than Bevy or Godot.
- WebGL2 rather than WebGPU.
- JSON stays the wire format; the TypeScript types are generated from the Rust ones.
- The Next.js app lives in this repo at `apps/web`, since this is the submission repo. The landing page from
  dhaniverse-v2 moves in during the UI work.
- This piece starts straight in the town; the opening is rebuilt with the onboarding, not ported first.
- The current game layer's screens are not ported; the redesigned quests and screens come next.
- The movement and camera values are the ones the valley build runs today (walk 3.4 m/s, sprint ×1.65). An earlier
  ruling for the base build said 4.2 m/s and ×1.55.
- The sun's shadow is cached per lighting look, so tree shadows don't sway.
- The water's reflection is rebuilt cheaper than Godot's 28-step trace.
- Rendering is capped at 2× pixel density, because 3× phones would draw 2.25× the pixels for no visible gain.
- The port works from our own GDScript, using `reference/futuristic-retro-nature` only for comparison: it has no
  licence file and isn't in any repo.
- Optimised assets are committed; the sources stay in Git LFS.

## Left to the builder

Chunk size, level-of-detail distances, the impostor setup, the simplification limit for each building (bounded by
sign-off), the shader structure, the reflection technique, and the pinned versions. Latest today: next 16.4.5,
react 19.3.1, three 0.187.0, @gltf-transform 4.5.1, meshoptimizer 1.3.0, vitest 5.1.0, @playwright/test 1.65.0.
