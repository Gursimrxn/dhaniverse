---
tags: [spec, frontend, godot, web, 3d, production, performance]
date: 2026-11-05
version: 1.1
status: production targets; approved browser measurements are not recorded here
aliases: [3D Frontend Production, Browser 3D Spec]
---

# 3D Frontend Production Specification (Browser-First)

## 0. Status and honesty rules

This is the production contract for the Dhaniverse 3D frontend. It is a **design target document**, not a status report:

- Production gates require recorded measurements; native checks and renders do not establish browser approval.
- Full Godot canopies and the bank-derived foliage are the current references. Final v3 branches exist in its master, not the earlier extracted foliage library. Tree geometry and export quality remain review work.
- The founder's 13 October direction is medium, angled third-person. Existing first-person comparison code is the baseline; static Blender camera studies do not implement the new controller (§5).
- Authorized prototype integration can proceed alongside Blender work. Art gates govern finished-asset approval; this spec governs runtime derivation, delivery and measured browser acceptance.

Ownership map (do not duplicate decisions across docs):

| Concern | Owner |
|---|---|
| Runtime budgets (tris/draws/textures/ms/MB) | This document |
| LOD/streaming/instancing runtime policy | This document |
| glTF export subset and runtime asset pipeline | This document |
| Third-person input and runtime camera acceptance | This document, following current user direction |
| District layout, kits, palettes, botanical studies | `design/10_City_Art_Direction.md` |
| Ownership, stable IDs, leases, stocks, seed rules | `design/11_Canonical_Game_Rules.md` |
| Wire messages and REST fields | `specs/protocol/WebSocket_Protocol.md`, `specs/api/API_Contract.md` |
| Persistence | `specs/database/Schema.md` |

## 1. Product surface and split of responsibilities

Two deliverables, one account session:

1. **Next.js shell** (`apps/web`): public pages, authentication handoff and game launch. Optional wallets/proofs require a separately selected integration; historical Privy/Phantom and public reputation ideas are not a dependency for the core game. The shell owns no gameplay rendering.
2. **Godot web client**: the walkable 3D city and all in-world presentation/interaction. Embeds into the shell (iframe or same-origin route) and talks to the backend over HTTPS/WSS only.

| Layer | Host | Responsibilities |
|---|---|---|
| Shell | Next.js | Auth UI, wallet, attestations display, settings handoff, deep links |
| Game client | Godot 4 (web export) | World rendering, streaming, avatar control, in-world UI, network sync |
| Backend | Rust/Actix + Postgres + Redis | Authoritative simulation, economy ticks, leases, stocks, chat, trade; validates every mutation |

The game client **renders and requests**; it never computes authoritative outcomes. Movement, resource numbers, prices, harvest stocks, and lease states come from the server ([Multiplayer_Architecture.md](../multiplayer/Multiplayer_Architecture.md); rules IN-1).

## 2. Engine and toolchain pin

| Item | Pin | Status |
|---|---|---|
| Engine editor | **Godot 4.7.2-stable**, observed `--version` output `4.7.2.stable.official.ed1daf0bf` | **Pinned as editor candidate.** `game/project.godot` declaring features `("4.7", "GL Compatibility")` is consistent with this stable editor — no dev-build inference. |
| Export templates | **4.7.2-stable templates, exact matching version** (not "same minor"): download the `4.7.2-stable` template pack and verify it installs against this editor before trusting any export | **Not yet installed or run.** Gate 1 (§11). |
| Rendering method | `gl_compatibility` (Compatibility / WebGL 2.0 on web) — already set in `game/project.godot` | On web, Compatibility is the **only** renderer Godot 4 supports; Forward+/Mobile need RenderingDevice/WebGPU, unsupported on web. |
| Language | GDScript only | C# cannot export to web in Godot 4 (docs, Attention box). |
| DCC | Blender 5.1.x  | Export pipeline §6. |

Evidence (all fetched 2026-11-05, 4.7 docs): [Exporting for the Web](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html) ("requires support for WebAssembly and WebGL 2.0"; "Godot 4 can only target WebGL 2.0 (using the Compatibility rendering method). Forward+/Mobile are not supported on the web platform"; C#-no-web), [Overview of renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) (feature tables below), [Command line tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html) (export flags), [Exporting packs, patches, and mods](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_pcks.html).

**Export command honesty:** the full browser build (html + js + wasm + pck + png) comes from `godot --headless --export-release "Web" index.html`; `--export-pack` produces **only** a `.pck`/`.zip` game pack (extension chooses format) and is used for district bundles/patches, not for the web deliverable ([command line tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)).

**Renderer feature policy (Compatibility — banned on the shipped web path).** Verified against the fetched 4.7 renderer comparison: SDFGI, VoxelGI, SSIL, volumetric fog, screen-space reflections, compute shaders, RenderingDevice access, decals, particle trails, light projector textures, PCSS (all light types), TAA/FSR2/FXAA/SMAA + screen-space roughness limiter, MSAA 2D, CompositorEffect post-processing, normal/roughness buffer sampling, subsurface scattering, variable rate shading, debanding. Also note the table's own quality facts for our art direction: Compatibility renders **RGBA8 low dynamic range** and **24-bit depth without reverse Z** — precision-sensitive looks (strong HDR tonemaps, deep-scene z stacking) must survive these, checked in-browser. Available and used: fog (depth/height), tonemapping, glow, adjustments, fullscreen-quad post-processing, MSAA 3D, SSAA, SSAO, baked LightmapGI rendering (baking itself requires RenderingDevice hardware — editor-side only), reflection probes (**2 per mesh max**), lights at **8 Omni + 8 Spot per mesh / 8 directional total**. Banning is per-feature regardless of what the desktop editor shows; relaxing any line item requires a spec amendment plus re-measurement. Forward+ on desktop is authoring-preview only — visual approval happens in the Compatibility browser build, never an offline render (City Art Direction gate 6).

## 3. Compatibility baseline

- **Hard baseline:** desktop browsers with WebGL 2 + WebAssembly; Chromium-based browsers and Firefox (Godot docs recommend these over Safari for WebGL 2 issues).
- **Measured budget class:** founder machine class — Intel UHD (12th-gen i7-1255U), 8 GB RAM, Windows desktop browser, **1280×720 @ 30 fps target** (§10).
- **Mobile browsers: no guarantee.** Godot: web export "can run on mobile platforms with some caveats"; WebAssembly costs extra CPU/GPU headroom. Out of budget scope (build cuts mobile).
- **Known web-platform limits, all from [Exporting for the Web](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html):**
  - *Tab suspension:* browser pauses the project when the tab is inactive (`_process`/`_physics_process` stop); networked sessions can disconnect → drives §8 visibility/reconnect rules.
  - *Fullscreen & cursor capture:* only from within a pressed-input-event callback (`_input`/`_unhandled_input`); querying `Input` is not sufficient → camera-look (§5) uses capture-on-click and degrades to drag-to-look (current probe already orbits via held right-mouse without capture).
  - *Audio autoplay:* browsers block audio until a user gesture → boot requires click/tap/keypress (§9).
  - *Web audio Sample mode (default since 4.3):* no audio effects, no reverb/doppler, no procedural generation, positional audio "may not always work correctly".
  - *Networking:* low-level networking unimplemented; only HTTP client/requests, WebSocket client, WebRTC. HTTP is further restricted: no threaded/blocking mode, progress at most once per frame, no chunked responses, same-origin policy, host verification not disableable.
  - *Persistence:* `user://` needs cookies/IndexedDB; iframes require **third-party** cookies; incognito prevents persistence; `OS.is_userfs_persistent()` "can give false positives".
  - *Secure contexts:* features increasingly require HTTPS (localhost exempt).
- **WebGL context loss:** the browser canvas fires `webglcontextlost` / `webglcontextrestored` ([MDN: webglcontextlost_event](https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement/webglcontextlost_event); simulatable via `WEBGL_lose_context`). Handling lives in the custom HTML shell (§12): listen on the canvas, show a recover screen, prompt reload — recovery by reload, not assumed in-engine restoration.

## 4. Threading model and hosting headers

**Baseline: single-threaded web export (Thread Support off).** Godot 4.3+ made this the preferred/default web export: it avoids the `SharedArrayBuffer` cross-origin-isolation requirement and "is also more compatible overall with stores like itch.io or Web publishers" ([docs](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html)). The wallet/third-party constraint decides it: **complete cross-origin isolation means "no ads, nor third-party integrations on the website hosting your game"** (docs Note) — and our shell embeds Privy/Phantom SDKs. Single-thread keeps the shell non-isolated.

Consequences accepted:

- No `Thread`/`WorkerThreadPool` usage; no Web Workers → **no asynchronous (de)compression or off-main-thread decode is promised anywhere in §7's loading path**. Downloads use async `HTTPRequest`; parsing/mounting/instantiation happen on the main thread and are budgeted as such.
- `ResourceLoader.load_threaded_request` is *available* but in a non-threaded export must not be relied on to move decode work off the main thread — no such claim here; §7.1 budgets main-thread work explicitly.
- Audio uses Sample playback (docs: low latency even without threads; §9 trade-offs).
- Optional variant (not baseline): threaded export + `Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp` headers (or the PWA service-worker simulation, itself still requiring a secure context). Revisit only if §10 shows main-thread framing as the bottleneck **and** a wallet-safe isolation design exists. Deployment (§12) ships without COOP/COEP.

Evidence: [Exporting for the Web — thread notes + Serving the files](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html); [single-threaded export blog post](https://godotengine.org/article/progress-report-web-export-in-4-3/#single-threaded-web-export).

## 5. Camera and input stance

- **Accepted direction, 13 October:** a medium, angled third-person view with a visible player and enough surrounding street to understand movement. Avoid first-person framing and a steep overhead camera. Exact pitch, distance and zoom remain review choices; the Blender v3.1 study provides 28°, 34° and 40° candidates.
- **Existing implementation:** `game/scenes/world_compare.tscn` still has first-person movement and the 1/2 location comparison. Keep that baseline available while implementing the new camera in the playable scene. The earlier blockout controller is not automatically the new design.
- **Runtime acceptance:** readable player, entrances and interaction targets; camera collision; usable roof/canopy occlusion handling; smooth follow and bounded zoom; stable controls across view changes; player-scale collision/floor support and measured browser budgets. Static camera renders prove composition only.
- **Art review:** ground views inspect joins and building details; overhead views inspect layout. Neither substitutes for the intended third-person play view. Work with depth blur off during geometry review.
- **Input:** use explicit interaction and camera controls, with a clear release path if mouse capture is used. Browser cursor capture requires an input event, as [Godot documents](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#full-screen-and-mouse-capture).

## 6. Asset pipeline: Blender → glTF → Godot

### 6.1 Art master vs runtime asset

The Blender library (foliage masters under rebuild, kit meshes, Poly Haven CC0 scans per City Art Direction §Reuse) holds **art masters**. Masters are never dropped into the game. Each production asset is derived:

| Master feature | Runtime treatment |
|---|---|
| Node-tree materials (noise/mix/ramp/anything) | **Baked** to a small PBR set (albedo + ORM) at agreed texel density; Godot consumes Principled-compatible inputs only |
| Solidify/bevel/array stacks and **geometry-node scatter/instances** | **Realized into actual meshes before export** (apply/realize or the Geometry Nodes exporter modifier; the glTF writer exports evaluated meshes — Godot never sees live node graphs); scatter density for ground detail is instead re-instantiated at runtime (§6.3) |
| Real twig/leaf geometry | Tree masters → trunk+branch meshes + identifiable foliage elements, authored per-asset: leaf/petal **cards on atlases are an option per species/LOD plan, not a forced conversion**; wind is a vertex shader, not geometry |
| Dense ground instances | Exported as **proxy point data** (position/scale/rotation lists), rebuilt at runtime in `MultiMeshInstance3D`; never authored as millions of exported objects |
| High-poly sculpt detail | Normal/roughness bake, or LOD0 mesh at close distances only |

Export format: **glTF 2.0 (`.glb`)**. Direction/scale conventions per [Model export considerations](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html): right-handed Y-up, assets face +Z, metres, transforms applied, **triangulate in Blender before export** (import triangulation of N-gons is called unpredictable there).

### 6.2 Import-side contract (real Godot features only)

- **Colliders:** authored in Blender as low primitives with `-col` / `-convcol` / `-colonly` / `-convcolonly` name suffixes so the importer creates `StaticBody3D` collision automatically ([Node type customization](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html)); its stated preference: "try to use a few primitive collision shapes" over trimesh/convex. Decorative geometry uses `-noimp`. Navigation uses the **`-navmesh`** suffix or runtime-baked `NavigationMesh` per district (no other navigation suffix exists — do not invent one).
- **Occluders:** `-occ`/`-occonly` suffixes or baked `OccluderInstance3D`. Occluder geometry is tested as **opaque**; alpha foliage (grass/leaf cards) must never be used as occluders — occlusion comes from buildings, walls, terrain, with hand-placed `BoxOccluder3D`/`PolygonOccluder3D` for building silhouettes where baking misses ([Occlusion culling](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html): automatic baking counts only `MeshInstance3D`; MultiMesh is excluded).
- **Sockets:** interaction/attachment empties (`socket_door`, …) are plain named nodes preserved by the importer and read by the interaction system; no engine magic.
- **Origins and scale:** kit origins at ground-centre, metres; world +X east / +Z south (Godot right-handed Y-up; matches City Art Direction "origin metres").
- **UVs:** UV0 for runtime textures; UV2 via the **Light Baking: Static Lightmaps** import option ([Import configuration](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html)) — in-browser GI is baked LightmapGI + ≤2 reflection probes per mesh only, never realtime GI.
- **LOD:** importer **Generate LODs** (meshoptimizer decimation) enabled on exterior kits; LOD thresholds are set from **measured screen coverage** in review (§10.3), not fixed distance constants. `Mesh LOD` works with `MeshInstance3D` and `MultiMeshInstance3D` ([Mesh level of detail](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html)); distance fade / visibility-range HLOD options are adopted only once a chunk renders >1 draw at range.
- **Textures:** source PNG/WebP (plus `.ktx` accepted as a *source* container — the 4.7 [Importing images](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) docs list KTX via libktx, **2D images only**, no cubemaps/arrays/de-padding — so KTX is optional, never required; likewise **Draco is not a Godot web feature and is not required**: GLB transport size is handled by HTTP content-encoding on the CDN). 3D textures import **VRAM Compressed** with mipmaps; the web preset enables **both** For Desktop and For Mobile VRAM compression variants when VRAM compression is used (docs: enabling both is "a bigger, but more compatible export" — assets that skip VRAM compression entirely are a measured disk/memory trade-off, not a hard break).
- **Material subset:** Principled BSDF → BaseColor/Metallic/Roughness/Normal/Emissive(+strength). glTF alpha has exactly three modes — `OPAQUE`, `MASK`, `BLEND` ([glTF 2.0 spec §alphaMode](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html#alpha-blending)); our foliage exports as `MASK` (threshold) or `BLEND`. Godot-side `alpha_hash`/`alpha_depth_pre_pass` are editor material features applied after import, not glTF properties — authored or set in import overrides, never claimed as "exported in the glb". Anything beyond the subset (subsurface, clearcoat coat/aniso) is **bake-or-cut** (subsurface is renderer-banned anyway, §2).

### 6.3 Instancing policy (grass/foliage/props)

- Ground detail: one `MultiMeshInstance3D` per material × render-chunk, instance counts set per measured coverage during district review (the probe's per-chunk `GrassSpawner` defaults — 1 000 instances/zone, earlier 8 000 studies — are technique parameters, not approved numbers), LOD ranges configured.
- Overdraw rules: alpha foliage keeps stacked layers bounded at any steady camera position — validated by visual review with the browser overdraw/debug view; mipmaps mandatory on alpha cards (distance shimmer fails the readability gate); **cull-boxes, alpha thresholds and density cutoffs are visual-review decisions per kit, recorded in the asset manifest**, not hard numeric rules invented upfront.
- Wind: animated vertex counts are budgeted through the §10.1 frame cost at review cameras, not a standalone vertex cap.

## 7. Runtime architecture: data-driven components

Godot-side code is a thin, data-driven presentation machine (composition root → services → data; small nodes with injected dependencies; one settings autoload like the existing `AppSettings`):

```
WorldManifest      — versioned JSON: world id, seed identity, district list, chunk grid spec,
                     asset bundle index (URL, sha256, size, format version)
 ├─ DistrictDef    — data resource: kit palette, planting tables, service anchors, spawn/POI list
 ├─ ChunkStream    — render-chunk lifecycle: request → download → mount → load → instantiate → evict(nodes)
 ├─ KitLibrary     — imported glTF scenes + material variants, keyed by stable asset id
 ├─ Presentation   — avatar, camera rigs (§5), lighting/weather from server time
 ├─ Interaction    — socket scan, prompt UI, verb dispatch (MANAGE/EARN/SPEND/PLAN) → NetworkState
 └─ NetworkState   — WebSocket client, authoritative state mirror, revision/idempotency bookkeeping (§8)
```

Hard rules from [Canonical Game Rules](../../design/11_Canonical_Game_Rules.md) (WP-1…WP-6, IN-1):

1. **Render chunks are not ownership units** (WP-1). Streaming cells are invisible implementation detail; parcels, addresses, leases, business locations are server entities with **stable IDs independent of any cosmetic seed** (WP-2). Manifest seed/version fields affect *decorative* placement only. Mutating stock, lease state, or harvest availability from client code is impossible by construction: those values only arrive through server messages (WP-4/5/6).
2. The world is **finite per published version, expandable by authored additions** (WP-2); the client trusts the manifest, never generates districts procedurally. Housing supply is physical multi-unit stock (WP-3) — the client renders vacancy it was told about, never infers it.
3. The current 9×9 grid of 48 m chunks in `game/World/` (`CityStreamer`/`CityPlan` probe) is an experimental interface study; adopting the layout needs its own approval; resizing never touches identity rules.

### 7.1 Streaming/loading budget model

District content ships as **per-district packs** (`.pck` built with `--export-pack`), *not* one monolithic startup pack:

1. Startup pack: boot scene, UI, shared shaders, avatar, starter district. Budget: §10.2.
2. `ChunkStream` queries the manifest, downloads a pack via async `HTTPRequest` into `user://`, verifies **sha256 + version**, then mounts with `ProjectSettings.load_resource_pack(path, replace_files := false)` — the documented runtime-pack API ([Exporting packs, patches, and mods](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_pcks.html)), with `replace_files = false` and **namespaced pack layouts** (`res://bundles/<bundle>@<version>/…`) so packs never overwrite engine-project files or scripts (the docs warn same-path files replace by default).
3. **Mounts are permanent for the session.** 4.7's `ProjectSettings` exposes no unmount method — mounted resources stay addressable until page reload. "Eviction" therefore means: free the *nodes* and let textures/meshes unref; mounted file entries persist. Cache lifetime is explicit and bounded: ≤ N packs downloaded per session and a `user://` file cache capped per §10.2 with LRU file deletion; reclaiming mounted-namespace memory beyond node-freeing requires a **reload**, which is a UX event, not a background optimization.
4. Because there are no workers/threads (§4), **everything after the async download happens on the main thread**: pack mount, scene `instantiate()`, `add_child`, texture/GPU upload. Mitigation is structural, not promised-async: packs are **small by design** (per-district, incremental resources), instantiation is quota-limited per frame, and gets happen at declared seams (menus, teleport, zone-edge). `ResourceLoader.load_threaded_request` may be used where available but is never *depended on* for off-main-thread decode in this baseline. (The same docs page notes ZIP packs are loadable too — treated as a format choice, not a filesystem fallback claim.)
5. Movement toward an unstreamed neighbour shows a walking-distance gate; distant content renders as LOD/HLOD proxies, never holes.

## 8. Networking

- **Transport: HTTPS (REST) + WSS (WebSocket client) only.** Browser exports lack low-level sockets/ENet; supported classes are HTTP client/requests, WebSocket client, WebRTC ([Exporting for the Web §Networking](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html); [Using WebSockets](https://docs.godotengine.org/en/4.7/tutorials/networking/websocket.html) — WebSocket is "TCP… good for reliability but not for latency"). Sync stays event/state-level; WebRTC unused for the city sim.
- Message contract, rate limits, errors: [WebSocket_Protocol.md](../protocol/WebSocket_Protocol.md) (versioned handshake; incompatible majors rejected; no ad hoc aliases).
- **Server-time truth:** economy ticks, leases, recovery evaluate on the server clock. `auth_success.server_time` seeds a client presentation clock; every time-sensitive UI renders against server timestamps.
- **Visibility/reconnect:** browsers fire `visibilitychange` ([MDN](https://developer.mozilla.org/en-US/docs/Web/API/Document/visibilitychange_event)) and pause the engine (§3). Hidden → stop sending intents, mark state provisional. Visible again → heartbeat-freshness check; if stale, reconnect + resync before accepting input; **no action queue survives suspension**. Reconnect per protocol exponential backoff.
- **Offline:** persistence can fail (§3); offline = read-only local shell with an explicit banner; no offline mutations exist by design, so no conflict resolution is needed.
- **Client abuse guards:** every client intent carries a **client request sequence** (ordering/staleness) **distinct from the server `state_revision`** the intent was computed against (optimistic-concurrency basis) — see API Contract §Contract Versioning; economic mutations carry `Idempotency-Key`; movement self-capped ≤ 5/s by the web client (protocol allows 10/s); all positions range-checked server-side. Client never *relies* on unvalidated local state for anything spendable (IN-1).

## 9. Audio (web-safe subset)

- Boot requires a user gesture before audio starts (autoplay policy §3): the shell's "Enter city" click is that gesture.
- Default **Sample** playback for UI/SFX (docs: low latency without threads; no effects/reverb/doppler/procedural; positional "may not always work correctly"). Ambience: short loops only until the browser build is heard; **Stream**-playback nodes are permitted (docs: full feature set at higher latency without threads).
- No reverb buses or procedural generation on web (unsupported in Sample mode; docs-cited). If effects become a requirement, §4's threading decision reopens with measurements.

## 10. PROVISIONAL budgets (Intel UHD i7-1255U class, 8 GB, desktop browser, 1280×720 @ 30 fps)

**Every number is PROVISIONAL** — a design ceiling to build and measure against; none is met-by-fact. A change is a spec amendment with recorded §11 measurements; a miss blocks the affected tier (§10.6). (These replace an earlier, unproven 1.5 M-triangle/1 500-draw "conservative" table and 60 MB-class cold payloads that could not meet a fast start on constrained links.)

### 10.1 Frame (main thread)

| Metric | Budget | Measurement |
|---|---|---|
| Frame time p95 | ≤ 33.3 ms (30 fps) | 60 s scripted acceptance walk, `Performance` monitors + browser profiler |
| Interactive stalls (frames > 100 ms while player controls/avatar moving) | 0 outside declared seams | stall log during capture |
| Declared-seam stall (zone-edge/mount) | ≤ 250 ms each, ≤ 3/min | same |
| GDScript `_process` total (active nodes) | ≤ 4 ms | `Performance.TIME_PROCESS` |

### 10.2 Download / memory

| Metric | Budget |
|---|---|
| **Cold total (first paint to playable, baseline world): compressed over-the-wire ≤ 24 MiB** — engine wasm + startup pack + manifest together | ≤ 24 MiB (brotli/gzip wire sizes) |
| Engine `.wasm` compressed share of the above | ≤ 16 MiB measured; if the stock template busts it, the lever is a size-optimised self-built template — docs endorse compiling with unused features disabled ("reduce the size of the WebAssembly payload significantly") ([optimizing for size](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/optimizing_for_size.html)) |
| Startup pack (UI + shaders + avatar + starter district) | ≤ 6 MiB compressed |
| Per additional district pack | ≤ 8 MiB compressed |
| Cold start to interactive (25 Mbps profile, **incl. wasm compile/decode + pack mount + first instantiate**) | ≤ 15 s target |
| `user://` cache (memory-backed + IndexedDB-persisted — counted in *both* the heap budget and persistence, never assumed to be "free disk") | ≤ 64 MiB packs on disk/IDB; LRU file eviction beyond; ≤ 2 pack mounts per session segment |
| Wasm linear memory + JS heap + `user://` memory backing | ≤ 512 MiB total CPU-side |
| GPU texture memory (VRAM-compressed, mipmaps) | ≤ 128 MiB |
| Concurrent `HTTPRequest`s issued by ChunkStream | ≤ 2 prefetch + 1 current (design choice; browsers manage their own socket pools — no engine-doc basis for a hard client cap, so none is asserted) |

### 10.3 Scene (per visible frame, any approved camera)

| Metric | Budget |
|---|---|
| Visible (submitted) triangles | ≤ 400 k |
| Draw-call submissions, main view | ≤ 300 |
| Draw-call submissions, shadow pass | ≤ 100 |
| Distinct materials resident | ≤ 80 |
| Texel density | 128–256 px/m hero frontage; ≤128 px/m background; atlases ≤1024² typical / 2048² hero max; mipmaps on |
| Realtime lights | sun + per-mesh 8-light cap respected by authored placement; night = baked/emissive-led, probe ≤2/mesh |
| Shadow config | distance and resolution **not pre-declared**: probe's Sky3D sun uses PSSM 4-split, 110 m distance, engine-default resolution — likely too costly for Intel UHD at 720p30; §11 sets the shipped value by measurement (likely fewer splits, shorter distance, ≤2048) |
| LOD thresholds | per kit, from measured screen coverage in review captures (not fixed metre constants) |
| Foliage/wind/instance density | per §6.3 review process; budgets enforced through §10.1/§10.3 frame outcomes, not standalone count rules |

### 10.4 Streaming/stalls

| Metric | Budget |
|---|---|
| Node instantiations per frame from ChunkStream | ≤ 4 scenes |
| Starter-district first load | inside §10.2 cold-start target |
| Neighbour pack download→mountable | ≤ 3 s p95 (25 Mbps profile) |
| Undeclared streaming hitches during acceptance walk | 0 |

### 10.5 Legibility

Signage/UI legibility and wayfinding are **judged in review captures** at the reference and candidate cameras at 720p — no automatic world-space pixel-cap is asserted (glyph size depends on camera distance/FOV choices still under approval); failure is recorded as a kit or camera amendment.

### 10.6 Tiers

- **Baseline (normative):** the tables above; knobs limited to render scale, shadow distance/resolution, instance density, wind cutoff — a settings ladder; **never** dropping game systems, economy depth, or district reach.
- **Enriched tier:** only after a device clears the in-boot frame probe, and only for knobs whose measured deltas are logged. No promises on unmeasured hardware.

## 11. Validation protocol (what makes a claim stop being PROVISIONAL)

Ordered gates; each emits an artifact under `docs/reports/` (date, engine pin+hash, device, build hash):

1. **Template pin:** install 4.7.2-stable export templates against the observed editor; `godot --headless --export-release "Web" web/index.html` succeeds from a clean checkout; **exact artifact list recorded** (index.html, .js, .wasm, .pck, .png + per-district `--export-pack` outputs); compressed sizes measured against §10.2; `.wasm` served as `application/wasm` (docs warn other MIME blocks startup optimizations).
2. **Browser smoke (Chromium desktop):** HTTPS (localhost exempt); cold load with cleared cache; audio-gesture start; capture-on-click/drag-orbit both usable; WSS auth/sync round-trip; one economy action round-trips with idempotent retry; district pack download→mount (`replace_files=false`, namespaced) → visible content; reload re-mounts from `user://` without re-download (IndexedDB persistence proven, incl. private-window failure path per §8).
3. **Budget capture:** §10 tables filled with measured values or explicit MISS rows (shadow settings decided here, not assumed).
4. **Degradation:** tab-away > heartbeat timeout → §8 reconnect/resync path; offline throttle → banner path; `webglcontextlost` via `WEBGL_lose_context` in devtools → shell recover/reload path (§3); persistence-off path.
5. **Art-gate linkage:** Blender G1–G6 pass (owner: CityArtRetry) **before** production city content goes through gate 2; probe content may dry-run gates 1–4 but confers no art approval.
6. Only then: rows move PROVISIONAL→MEASURED and §0 disclaimers drop per item.

## 12. Export and deployment contract

- One web preset: Compatibility renderer, **Thread Support OFF**, VRAM compression variants per §6.2, PWA disabled for baseline (its service-worker header simulation only matters for the threaded variant; its offline cache is revisited at gate 3). Export via `--export-release "Web" index.html`; file names must stay as exported (docs: renamed export files cause issues).
- Hosting: static CDN over HTTPS; correct `.wasm` MIME; brotli/gzip precompression for wasm+packs (docs: wasm compresses to ~¼ with gzip; GitHub Pages gzip on the fly, itch.io does not); long-cache immutable URLs with content-addressed filenames; manifest hash-checks (§13).
- Shell integration: same-origin under the Next.js app where possible — iframes push players into third-party-cookie territory for `user://` persistence (§3 docs warning).
- Custom HTML shell for: context-loss handler (§3), loading UI for the §10.2 cold budget, gesture-gate hookup (§9); [Custom HTML page](https://docs.godotengine.org/en/4.7/tutorials/platform/web/customizing_html5_shell.html) and [JavaScript bridge](https://docs.godotengine.org/en/4.7/tutorials/platform/web/javascript_bridge.html).

## 13. Security posture (client side)

- WSS/HTTPS mandatory; short-lived JWTs in memory only; refresh via REST; never persisted to `user://`.
- All mutations route through one dispatcher (request sequence + state-revision basis + idempotency, §8); no ad-hoc `HTTPClient` calls bypassing the contract; server-side origin validation + rate limits per [WebSocket_Protocol §Security](../protocol/WebSocket_Protocol.md).
- Clipboard/gamepad APIs are secure-context-gated (docs warnings) — feature-detect, degrade silently.
- Client ships no authoritative economy constants; displayed values come from server/catalog payloads; manifest + pack hashes detect CDN tampering.

## 14. Async slice


## 15. Open integration risks

| ID | Risk | Handling |
|---|---|---|
| R1 | ~~Godot binary absent / version drift~~ **Resolved 2026-11-05:** editor observed as `4.7.2.stable.official.ed1daf0bf`; **export templates not yet installed; no web export run** | Gate 1 installs exact-matching templates and produces the artifact list |
| R2 | `11_Canonical_Game_Rules.md` canonical wording (insurance corrected to 60/100/150 magnitudes; rest/price/grace) still settling with GameRulesRetry; cross-file links pre-committed | Main reconciles at review |
| R3 | Probe values (PSSM-4/110 m shadows, per-chunk grass counts, ortho zoom sizes) drifting into "canon" | §2/§10/§11 label them experimental; shadow budget is a gate-3 *decision* |
| R4 | Web-pack behavior: mounting proven per docs but **unproven in our build**; no unmount → namespace-permanent growth; IndexedDB-backed `user://` growth counted against memory (§10.2) | Gate 2/4 smoke with reload-persistence + cache-cap tests |
| R5 | COOP/COEP vs embedded wallet SDKs if threading is ever revisited | §4 decision gate; baseline stays single-thread |
| R6 | Safari WebGL 2 issues (docs) vs shell support-matrix copy | Game never advertises Safari; support matrix in shell docs |
| R7 | 24 MiB cold budget vs real 4.7.2 wasm size is **assumption until measured at gate 1**; fallback is a custom size-optimised template (§10.2), which costs build maintenance | Gate 1 measurement; build link blocked until inside budget or budget amended |

## 16. References

- Godot 4.7 docs (fetched 2026-11-05/13): [Exporting for the Web](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_web.html) · [Overview of renderers](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) · [Exporting packs, patches, and mods](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_pcks.html) · [Command line tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html) · [Background loading](https://docs.godotengine.org/en/4.7/tutorials/io/background_loading.html) · [Mesh LOD](https://docs.godotengine.org/en/4.7/tutorials/3d/mesh_lod.html) · [Occlusion culling](https://docs.godotengine.org/en/4.7/tutorials/3d/occlusion_culling.html) · [3D import configuration](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html) · [Model export considerations](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/model_export_considerations.html) · [Node type suffixes](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html) · [Importing images](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) · [Using WebSockets](https://docs.godotengine.org/en/4.7/tutorials/networking/websocket.html) · [Optimizing for size](https://docs.godotengine.org/en/4.7/engine_details/development/compiling/optimizing_for_size.html) · [Custom HTML shell](https://docs.godotengine.org/en/4.7/tutorials/platform/web/customizing_html5_shell.html) · [JS bridge](https://docs.godotengine.org/en/4.7/tutorials/platform/web/javascript_bridge.html)
- [glTF 2.0 specification](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) · [MDN webglcontextlost](https://developer.mozilla.org/en-US/docs/Web/API/HTMLCanvasElement/webglcontextlost_event) · [MDN visibilitychange](https://developer.mozilla.org/en-US/docs/Web/API/Document/visibilitychange_event) · [Can I use — WebGL 2](https://caniuse.com/webgl2) · [Godot single-threaded web export blog](https://godotengine.org/article/progress-report-web-export-in-4-3/#single-threaded-web-export)
