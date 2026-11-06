# Movement port: three.js feel into Godot

Source: `D:\DhaniverseData\backups\threejs-shelved-2026-11-07.tgz` (game-core `tuning.rs`, `lib.rs`, `anim.rs`; engine `actors/player.ts`, `anim.ts`, `camera.ts`, `ik.ts`, `input.ts`). It was read only; none of it was built or run.
Backups of the four Godot scripts before the change: `D:\tmp\claude\D--code-dhaniverse-eth\639f1ab5-4f1f-4bb2-8149-2642134eedcc\scratchpad\backup\`.

## Tuning table

| Tuning | three.js (source) | Godot before | Godot now |
|---|---|---|---|
| Walk speed | 3.4 m/s | 3.4 | 3.4 |
| Sprint | x1.65 (5.61 m/s) | x1.65 | x1.65 |
| Speeding up | linear, 20 m/s² | exp lerp `1-exp(-9 dt)` | linear 20 m/s² (`move_toward`) |
| Slowing / changing direction | linear, 26 m/s² | same exp lerp | linear 26 m/s² |
| Turn | eased at 12/s towards the **input** heading | 12/s towards the **velocity**, only above 0.3 m/s | 12/s towards the input heading |
| Turn on the spot | over 100° under 1 m/s, until within 30°: legs step at 0.7 m/s | gait settle-step | ported |
| Gravity / terminal fall | 22 / 30 m/s | 22 / none | 22 / 30 |
| Max slope | 46° | 45° (default) | 46° |
| Step up / reach | 0.5 m / 0.2 m | 0.5 / 0.2 | unchanged |
| Ground snap | 0.3 m | 0.4 m | 0.4 m (kept) |
| Capsule radius | 0.35 m | 0.35 | 0.35 |
| Loco blend | Idle/Walk/Run clips: moving `smoothstep(0.05, 0.5, v)`, run `smoothstep(1.0, 1.8, v)` | Idle clip only, legs procedural (gait.gd) | ported, AnimationTree Blend2s |
| Stride (phase) | shared phase, `v / cycle`: walk 0.98 m/s x 1.25 s = 1.225 m, run 1.89 x 0.875 = 1.654 m | gait stride 1.0 to 1.7 m | ported (cycle from the clips' real lengths, x body height) |
| Foot contact (footsteps) | at 0.12 (walk) to 0.22 (run) of the cycle, left foot +0.5; over 0.3 m/s, grounded | gait landing | ported |
| One-shot fade | 16/s (about 0.15 s) in and out | AnimationPlayer crossfade 0.22 s | OneShot 0.15 s in, 0.15 s out |
| Fall pose | Jump clip held at 0.45, after 6 ticks (0.1 s) in the air, fade 16/s | none | ported |
| Lean forward | `clamp(accel x 0.012, -0.12, 0.1)` + up to 0.07 at a run, ease 10/s | gait spine lean (0.035/m/s, 0.018/m/s²) | ported |
| Lean into turns | `clamp(-yawRate x speed x 0.02, ±0.18)`, ease 8/s | gait (0.028/m/s² across) | ported |
| Foot IK | per foot ±0.25 m to the ground, ease 15/s, hips lowered to the lower foot, two-bone in the knee's plane | procedural planted feet | ported |
| Step-up climb | drawn height on a critically damped spring, 0.07 s up, 0.03 s down, reset past 1.5 m | lifted in one tick | ported |
| Camera spring (top) | 0.3 s across, 0.45 s up | same | unchanged |
| Camera spring (third) | 0.1 s / 0.22 s | same | unchanged |
| Camera distance | top 7 to 30 (17), third 2.2 to 9 (4.5), first 0 | same | unchanged |
| FOV | 38 / 62 / 72; sprint +3 / +7 / +5 | same | unchanged |
| Lag and lead | yaw/pitch ease 40/s (7/s top, gliding), distance 7/s, lead ease 2/s (0.8 / 0.25 s of travel) | same | unchanged |
| Swing / recentre / hands-off | 0.45 / 0.45-0.5 / 0.35 s and 1.4 s | same | unchanged |
| Collision | ray, kept 0.3 m off, pulls in at once, out at 5/s; top view tilts over buildings | 0.2 m sphere sweep, 0.3 m off, same easing | unchanged |
| Near plane | 0.1 m | 0.3 m | 0.3 m |

The three.js camera (`camera.ts`) was itself a port of `camera_rig.gd`, so every camera number already matched.

## What changed, per file

**`game/scripts/valley/player.gd`**
- Acceleration is now linear: 20 m/s² speeding up, 26 m/s² slowing or turning (game-core `step`), in place of the exponential lerp.
- The body turns at an eased 12/s towards where the input points, not where the velocity points.
- A turn on the spot (over 100°, under 1 m/s, until within 30°) plays the legs at 0.7 m/s so the feet step round.
- Lean from `player.ts`: pitch into speeding up and stopping, more at a run; roll into turns. It goes on `avatar.rotation`.
- Terminal fall speed is 30 m/s. `floor_max_angle` is 46°. The script counts seconds in the air and passes them to the body.
- The drawn height rides a critically damped spring, so a step up is climbed in a few frames. `smooth_position()` returns that height, so the camera follows it as in three.js.
- Physics interpolation is kept. All smoothing uses `exp` decay or the spring, so nothing counts frames.

**`game/scripts/valley/hero.gd`**
- An AnimationTree now plays the clips instead of the bare AnimationPlayer.
  - Idle, Walk and Run are blended by ground speed.
  - Walk and Run are each stretched to a 1 s timeline, and one TimeSeek drives both from a shared phase, so the walk-to-run change is a blend on one stride, never a clip switch.
  - The fall pose (Jump at 0.45) is a Blend2.
  - Gestures are a OneShot with 0.15 s fades.
- Footsteps fire at the source's contact points through the same `gait.stepped` signal, so `player.footstep` is unchanged.
- Foot IK from `ik.ts`/`plantFeet`: a floor ray under each foot, the hips lowered on the model node, and a two-bone solve in the knee's current plane.
- `gesture("Interact")` falls back to PickUp, as three.js did.
- The procedural gait now runs only while sitting (scooter, remote riders).
- `step(speed, delta, air := 0.0)` gains an optional argument. Every other public function keeps its signature: `wave`, `gesture`, `hold`, `reach`, `bite`, `set_carrying`, `set_sitting`, `ride_pose`, `set_lying`, `bob`, `set_part_visible`.

**`game/scripts/valley/gait.gd`**: unchanged. It is still the NPC body (`life/person.gd`) and the sitting pose.

**`game/scripts/valley/camera_rig.gd`**: unchanged. It already matches the source (see the table). `hold_view`, `set_mode`, `take_cursor_back` and the rest are untouched.

The model, materials and clips are not touched, and no new animations were added. Jump, PickUp and Victory were already in `cozy_boy.glb` and were blended in the source.

## Checks

- **Parse check:** `--check-only` on all four scripts is clean.
- **Body check:** a scratch script steps the body at 0, 1.2, 3.4 and 5.61 m/s for 2 s each.
  - Footsteps: 0, 4, 8 and 14 against 0, 3.7, 8.2 and 13.6 from the stride maths.
  - The blend weights are right, there are no NaNs, the OneShot goes active, and the fall pose blends in.
- **Walkthrough bot** (`tallyport_drive.gd -- --arrive --player=drive8`, through `tools/godot_d.sh`, off-screen): **76 checks ok, "drive: 0 failed"**, exit 0.
  - The log has 8 `Parameter "material" is null` errors in `gles3/material_storage`. None of these four scripts touch materials.
- **Frame check:** one frame of the idle pose was captured; the body stands correctly on the ground.
  - A later capture showed `Identifier "Guide" not declared` parse errors from another agent's file that was being edited at that moment, not from these files.

## What couldn't be matched, and why

- **Wall-independent drive.** game-core keeps the driven velocity separate from what walls let through. Here the drive is `velocity` itself, because the bot and the test panel stop the player by zeroing `player.velocity`. The only difference shows when leaving a wall at an angle: speed builds again from the slid velocity.
- **Ground snap.** It stays at 0.4 m, not 0.3. Going down 0.5 m stairs relies on it, and the walkthrough checks pass with it.
- **Fixed 60 Hz tick.** game-core stepped at a fixed 60 Hz and drew between ticks. Godot's physics tick and physics interpolation do the same job here and were kept.
- **Foot IK ground.** It reads a physics ray, not the terrain height field. It applies on any floor under the body's middle (within 0.1 m), not on terrain only.
- **Footstep surface.** In three.js the footstep event chose grass or stone itself. Here the signal still carries only `(at, heavy)`; the sound code is not in these files.
- **Camera near plane and collision probe.** The near plane stays at 0.3 m and the probe stays a 0.2 m sphere (three.js: 0.1 m and a ray). These were kept so the camera doesn't clip into walls differently.
- **Remote players and NPCs.** Remote players (`other_player.gd` uses `hero.gd`) now get the clip blend too, but no lean, which lives in `player.gd` as it did in `player.ts`. NPCs keep the procedural gait.
- **Uphill sink, inherited.** The source's step-up spring trails the body a few centimetres while walking uphill: about the vertical speed x 0.07 s, so about 7 cm at 1 m/s of climb. It is ported as it was.
