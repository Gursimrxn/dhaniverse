---
tags: [art-direction, city, districts, assets, blender, production]
date: 2026-11-05
version: 1.0
aliases: [City Art Direction, Production City Plan]
---

# 10 — City Art Direction

**Current direction — 5 November 2026:** A contemporary river-and-rail town with
substantial light walls, charcoal frames, warm joinery, restrained teal and lush
branched foliage. Dragon Quest VII Reimagined informs stylized light, materials
and handcrafted composition; it does not impose medieval lore or an elevated
gameplay camera. Preserve the liked arrival, market, starter housing, bank and
Common Table masters. New generic/glass-heavy shops and terrain/layout revisions
remain review candidates. Use the praised Godot foliage/grass and bank leaf

**13 October camera correction:** target a medium, angled third-person view,
with a visible character and readable street surroundings. The existing
first-person comparison remains an implementation baseline. The supplied video
informs cohesion; the founder does not want its steepest overhead framing.
Authorized Blender and Godot
prototypes can proceed together while art is reviewed; the gates below determine
production acceptance, not whether any prototype integration may begin. Current
user authorization supersedes old isolated-model restrictions. Stable sites and
occupied units remain protected. Earlier reference changes and one-model tasks
are recorded in the production history.

This document is the canonical art direction for Dhaniverse's playable city. Ownership rules and economy truths live in [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md); client rendering and delivery constraints live in [../specs/frontend/3D_Frontend_Production.md](../specs/frontend/3D_Frontend_Production.md). Where this document describes a visual goal and those documents define a system rule, both apply; the art direction never overrides canonical game rules, and canonical game rules never dictate a specific prop.

---

## 1. The City as a Grown Place

The city is a **river-and-rail town**. It is not a themed zone mall. Its shape comes from economic history that the player can read off the buildings:

1. **Ferry market first.** The settlement exists because a river narrowed here and a quay could be built. The oldest blocks are waterfront: trade houses, granaries, a bank at the landing, food stalls where the boats tie up.
2. **Craft and residential quarters next.** As the market held, workers and makers moved in behind the quay — smaller lots, courtyards, mixed living-over-workshop buildings. These quarters are where most housing units are.
3. **The station came last, and the city's weight tipped east.** When the railway reached the far side of the market wards, commerce stacked up around it: mid-rise shops, upper-floor residences, signage, cycle parking. The east is the newest, densest, most vertical part of town.

Consequence for art: age gradients must be visible through frontage, structural rhythm, repairs and conversions. Quay buildings, courtyard blocks and station-side construction share a contemporary material language while expressing different histories. Earlier traditional timber/tile prescriptions are optional references, not a requirement to remake retained anchors. Every block should look like it was built, repaired or extended for a purpose.

The city is **finite, persistent, and author-expandable** (per [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md)): a hand-authored world that grows by released versions, never by unbounded procedural generation, and never by moving things players already own.

---

## 2. Macro Geography

The compass directions carry meaning. This is the masterplan logic every district proposal must respect:

| Bearing | Role | Content |
|---|---|---|
| **North** | Green and water supply | Forested catchment, reservoir, orchards and farms feeding the market. No dense construction; this is where the city's resources come from and where the air is clean. |
| **West** | Quiet and traditional | The older low-rise quarters: timber workshops, courtyard housing, gardens. Low, horizontal, shaded. |
| **Centre** | Quay and market | The waterfront, the bank, the market colonnades, the administrative cores. Where the loop starts. |
| **East** | The station | Railway, commuter flows, stacked commerce, the modern face of the city. |
| **South-east** | Freight | Sidings, goods yards, the works. Loud, industrial, downwind. |

Water drains from the northern catchment and reservoir through the river/canal corridor toward the lower quay; crossings are landmarks. The start area sits between quay and market so a new player can reach a bank, affordable food, entry-level work, recovery support and their allocated room on foot inside one connected loop.

---

## 3. Districts

District names are **working names**. They label art direction and planning intent; none is locked branding. The types in the experimental `city_plan.json` (quay, market, residential, garden, civic, health, campus, station, industry, canal, woodland, orchard, farm, reservoir, quarry) are load-type experiments, not the final district list.

Each district below gets a **distinct construction language and silhouette**. The acceptance test for a kit: identified at 20 metres with textures disabled, from massing and roofline alone. Reskinned copies of one box with different colors are rejected.

### Founders' Quay (original waterfront)
- **Purpose:** the start district — first bank, first food, first work, first home. The oldest and lushest part of town.
- **Form:** continuous terraced blocks right on the water; ground-floor shops with upper floors overhanging the street; stone landing steps; the founding bank as a squat, heavy building at the quay head because that is where risk was priced.
- **Palette:** lush and colourful — painted facades, shutters, flower boxes, deep moss on north walls. The most saturated greenery in the city grows here because water and money met first.
- **Services:** bank (start), food stalls/canteen, job board, housing office for beginner units.
- **Hero landmarks:** the quay steps and crane, the founding bank, the market clock.

### Market Ward (trade)
- **Purpose:** wholesale and retail trade; brokers and money-changers; the dhaba row where the ward eats.
- **Form:** South Asian commercial vernacular — narrow frontages, cantilevered awnings and canopies over the stalls, verandas, deep-shaded lanes, locked-down shutters after hours, goods stacked in licensed sidewalk zones. Interior courtyards behind the shopfronts carry the back-of-house: warehouses, lofts, broker offices.
- **Palette:** warm masonry with high-chroma textiles, signage, and produce; strong awning shadows as a signature light pattern.
- **Services:** trade floor and price board, brokers' courtyards, dhaba (food), storage.
- **Hero landmarks:** the awning market lane, the brokers' courtyard, the dhaba row at evening light.

### Cedar Quarter (traditional timber)
- **Purpose:** craft production and older skilled housing; the quiet, traditional west.
- **Form:** traditional Japanese timber construction — narrow vertical facades on small lots, deep eaves, tiled hip-and-gable roofs, lattice over the ground-floor workshop windows, indigo-dyed noren and textiles as the dominant accent, exposed post-and-beam silhouettes, low walls and stepped entry plats. Two storeys max; everything reads horizontal against the sky.
- **Palette:** wood chestnut and charcoal tile, white plaster infill, **indigo** as the district key color; moss on tile ridges.
- **Services:** craft workshops (employment), tool and material goods, a small quarter office.
- **Hero landmarks:** the long tile roofline along the canal, the indigo dyers' yard, the quarter gate.
- **Note:** this is a period construction tradition used as architecture, not a costumed theme park. No shrine/holiday set dressing beyond what the residents would actually hang.

### Eastgate (station and modern commerce)
- **Purpose:** the railway station, commuter services, and the densest commerce in the city; the growth engine of the eastern side.
- **Form:** Tokyo-style mid-rise: 4–8 storey frames standing shoulder to shoulder, ground-floor shops, stacked upper floors for offices and rented rooms, continuous balconies with laundry and plants, a controlled chaos of vertical signs and awnings at pedestrian scale, bicycle parking as a permanent ground-plane feature. The station itself is a long low platform canopy with a head-house, not a fantasy spire.
- **Palette:** concrete, dark steel, glass, warm interior spill light, high-chroma **signage** as the color story. Deliberately **not generic cyberpunk**: no neon megastructure dystopia, no holograms, no uniform night-city. Daylight Eastgate reads as busy, maintained, optimistic density; evening Eastgate reads as the warmest lights in town.
- **Services:** station (employment hub and connection point), rental offices (housing supply), 24-hour food, print/sign shops.
- **Hero landmarks:** the station head-house, the sign canyon at the crossing, the balcony skyline seen from the platform end.

### Willow (varied residential)
- **Purpose:** the city's housing breadth — where most stable housing units actually are.
- **Form:** deliberately varied, because a real residential district is never one building type: courtyard apartment blocks, terraced houses, corner shops in gables, a few larger conversions. Different eras of repair visible on the same street. Generous private and semi-private green: hedges, shared yards, street trees.
- **Palette:** garden greens, brick and render in muted tones, color returned by the residents (doors, planters, laundry) rather than by the architecture.
- **Services:** housing listings, schools feeders, corner retail, clinics on the fringe toward Civic Rise.
- **Hero landmarks:** the double courtyard block, the willow-lined approach from the quay.

### Civic Rise / Learning Commons (institutions)
- **Purpose:** the institutions the economy depends on — and each must be a **distinct building type, not a reskinned box**: school, library, civic hall, clinic, hospital, and the insurance & claims office.
- **Form:** civic-scale but humane: stone and brick public buildings with legible entrances, a learning cluster (school + library + commons green) readable as a campus, and the hospital/clinic pair clearly differentiated by ground-floor triage architecture and signage. The insurance and claims office is where the game's core lesson has a physical door: you stand in it to learn what risk costs.
- **Palette:** civic stone, institutional greenery, clean signage; lower chroma than the market wards, higher legibility.
- **Services:** school, library, civic events, clinic, hospital (consequence landing point), insurance counter and claims desk.
- **Hero landmarks:** the library steps, the hospital forecourt, the claims hall.

### Brickworks / Works (freight and employment)
- **Purpose:** heavy employment and the freight edge: sidings, yards, kilns, workshops. South-east, downwind of home.
- **Form:** functional brick and steel — tall chimney silhouettes, goods sheds with big sliding doors, rail spur geometry that the player can actually follow, stacked pallets and skip clutter with industrial wear. Workers' amenity buildings (pay office, canteen) at the gate, not inside the hazard zones.
- **Palette:** fired brick red, iron oxide, soot gradients on north faces, safety yellow accents.
- **Services:** freight and manual employment, pay office, storage that connects to the market ward supply chain.
- **Hero landmarks:** the kiln chimney (visible from three districts), the shed row and spur.

### Pine Ridge / Headwaters (forest and catchment)
- **Purpose:** the water supply and the wild-green edge; walking, foraging-flavored calm, and the visual "deep background" of the north.
- **Form:** detailed forest — layered, species-specific stands (see section 7), the reservoir with its intake and valve house, quarry scars where stone was taken before the water rules tightened. Terrain is the asset here: root-lifted ground, rock shelf, bank and shoreline ecology.
- **Palette:** deep conifer blue-greens, bright understory in canopy gaps, wet rock grey.
- **Services:** water infrastructure (visible and explained), quiet recreation, the forest edge as the map boundary — the city ends and the catchment begins, which makes the limit feel authored rather than loaded.
- **Hero landmarks:** the reservoir wall, the intake house, the ridge overlook back over the whole city.

### Northfield / Orchards (agriculture)
- **Purpose:** food production between the green north and the market centre; shows the supply chain the Market Ward trades in.
- **Form:** real working fields and orchard rows with hedgerows, a barn or two, an farmer's landing toward the market, irrigation channels fed from the water system. Agriculture here is landscape architecture: hedgerow lines, orchard spacing, and field-barn silhouettes must read as maintained land, not noise scatter.
- **Palette:** seasonal — orchard blossom in spring, heavy fruit greens and harvest golds later (versioned season palettes, not real-time weather systems).
- **Services:** farm employment, produce supply to the market ward, agrarian housing on the lanes.
- **Hero landmarks:** the long barn, the blossom rows seen from the market road.

---

## 4. Transitions, Streets, and Movement

- **Districts transition through streets, not themed tiles.** There are no borders to cross and no "Japan zone ends here" line. A lane from Cedar Quarter into the Market Ward changes width, surfacing, awning style, and planting gradually over a block or two. Shared construction edges (party walls, wall returns, hedge lines) carry the hand-off.
- **Walkable beginner loop.** A new player must be able to walk from spawn to the start bank, a food source, a job notice, and a housing listing without loading screens, teleporters, or vehicles. The loop is the masterplan's first gate (section 9, G5), and its connected terrain/stairs/ramps are tested as art, not just collision.
- **Connected terrain.** Stairs, ramps, kerbs, bridges, and quaysides are authored as kit pieces that join cleanly. Any level change needs a walkable route and a visible reason. Ramps are not accessibility decals — the path must actually route.
- **No culture equals wealth gating.** District traditions are architecture and economic history, not price tiers of worth. Every district can hold every housing quality band; a Cedar Quarter workshop and an Eastgate studio can be the same rent. Rich/poor is expressed through **condition, maintenance, and floor area** — never by making one culture's streets the poorhouse or the vault of the game. This is a hard content rule.
- **Housing units are stable.** A home that exists in one version exists in the next with the same identity; facades may be repainted and blocks extended, but no released version moves, deletes, or re-rolls a housing unit a player holds. Ownership, leases, and resource stocks are authoritative server-side rules per [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md); the art pipeline must preserve unit identity through every rework.

---

## 5. Silhouette, Landmark, and Service Rules

1. **One construction language per district kit.** Materials, structural system, roof form, and window rhythm are defined per district and shared across every piece in that kit. Mixing languages inside one kit is rejected unless the building is explicitly a later conversion (and then the seam must read).
2. **Hero landmarks per district.** Each district has at least one distinctive roofline, large-site structure or natural feature visible on neighbouring approaches. A low bridge, old spreading tree, garden wall or station canopy can anchor a district; a traditional two-storey quarter does not need a conflicting three-storey tower.
3. **Meaningful services, not deceptive set dressing.** Named services correspond to the full game's documented functions. A release exposes interactions only for implemented services; planned buildings remain visibly non-interactive scenery rather than claiming working employment, banking or treatment. Background architecture need not host a mechanic at every door.
4. **Readability without textures.** Kit pieces pass silhouette review first (grey-shaded massing at gameplay camera distance), then material review. This ordering is what prevents "asset with good textures hiding bad shape."
5. **The skyline is composed.** Looking from any hero landmark, the layering of rooflines must be deliberate: tile before concrete before forest before water, with the chimney and station canopy as distance finders.

---

## 6. Color, Light, and Mood

- **Vibrant, not washed out.** The target is a saturated, warm, living town. The anti-pattern is the desaturated foggy "AAA realistic" grade: the city must never dissolve into brown-grey haze. Depth cues are aerial perspective at *modest* strength plus foreground/midground/background color separation — never a fog wall that erases the skyline.
- **Two shared lighting presets gate all comparisons:** the **daylight set** and the **evening set**. Every sample and every district review renders under the same pair (section 9, G4) so color decisions compare fairly. Individual props are never approved under bespoke lighting.
- **Water reads as water.** River, canal and reservoir share believable depth, restrained flow and edge contact. The browser baseline uses authored depth/colour, simple normals, baked surroundings and limited reflection probes; live screen-space or planar reflections are not required. Verify water against the reference and actual Compatibility export, not Cycles alone.

---

## 7. Foliage and Ground Ecology

Foliage is a first-class system, not scatter brush:

- **Species-specific, layered.** Trees are authored as identified species (or close stand-ins), never generic "green blob". Conifer stands, broadleaf, blossom, orchard stock, and street trees each have distinct branching architecture, canopy shape, and bark.
- **Canopy gaps.** Forest edges and street rows are composed with gaps that let light reach the ground — which is what licenses the ground layer.
- **Bark and branch detail** at the trunk zone (0–2 m) where a walking player actually looks; silhouette and clump structure at distance.
- **Leaf and petal shape legibility.** At close LOD, leaf shape (and the five-petal cherry form) must read as *the species'*, not as noise.
- **Ground ecology follows the canopy:** moss, fern, root flare, leaf litter, and hedge layers under trees; grasses thinning toward trodden streets. Ground cover changes where paths, walls, quay stone, and freight yards meet nature — transitions drawn by hand, not painted uniformly.

**Current foliage reference:** full stylized Godot canopies and the standalone
bank leaf geometry. The final v3 master adds connected branches to its green and
cherry templates; the extracted foliage library comes after that pass. Older rejected
botanical studies are reference material, not automatic production candidates. Keep
species silhouettes, useful canopy depth, branches and ground transitions; avoid
photorealistic tree replacements. Runtime derivation and browser profiling remain

---

## 8. Materials, Sourcing, and Reusable Asset Acceptance

### Reference study and next modeling pass

as a reference for world cohesion, beauty and sunbeams. The following is the
proposed first art pass within implementation milestone 1. Its landscape and
lighting inform the existing contemporary river-and-rail town. **The founder's
sequencing instruction is models/layout first, followed by colors, foliage,
ground/wall details, water and optimization, with lighting polish afterward.**
Use plain fixed work lighting for geometry review until those passes are ready.

The clip's wooded stream has overlapping canopy silhouettes, shrubs beneath
trees, flowers around clearings, curved banks and a visible shallow-to-deep
riverbed. Around 24 seconds, foliage shadows break up the green ground; around
46 seconds, rock terraces, a waterfall and a timber crossing frame the water.
Warm lit greens and cooler shaded greens separate the layers. These are useful
composition references; the town's own quay, architecture and bank foliage

Start with a clay layout review of the starter neighborhood, then develop
**the river landing, bank forecourt and market approach** as the first detailed
section. The saved v3 court/map renders show broad lawns between detached
buildings and abrupt terrain/paving joins. Establish street edges, housing
courts, service yards, gardens, gathering spaces and planted river margins.
This layout pass must improve the spaces between buildings before decoration.
Keep room for players to pass, meet and see service entrances.

Work in this order:

1. **Layout and model geometry.** Shape continuous terrain, the riverbed, curved
   banks, quay, steps and a usable ramp. Join building foundations to the ground.
   Review building proportions, distinct silhouettes, roof/wall connections,
   doors and windows; fix intersections, floating parts and coplanar faces.
   Develop coherent housing/street frontage around retained anchors, with
   usable market and home thresholds. Keep new shop revisions reviewable and
   preserve the liked masters. Check the whole layout from above and walk the
   detailed section at player scale under plain lighting.
2. **Colors and materials.** Establish a shared light-wall, charcoal-frame,
   warm-joinery and restrained-teal palette. Match surface scale, roughness and
   edge treatment across buildings, paving and river stone. Review adjacent
   models together so individual assets belong to the same place.
3. **Foliage.** Refine a derivative of the final v3 bank tree with connected
   limbs, root flare and full layered foliage; preserve the liked leaf geometry.
   Review it beside the praised Godot trees before creating variants. Add low
   shrubs, ferns, reeds, leaf litter and restrained flowers in appropriate
   planted areas. Keep the existing Godot grass response as the runtime
   reference and retain clear walking/service space.
4. **Ground, walls and everyday details.** Finish paving/soil transitions,
   drains, wall bases, coping, railings, planters and courtyard details. Place
   market counters, trays, crates and a handover point where the first activity
   uses them. Give open areas a legible purpose and vary density around use;
   preserve deliberate clearings and social space.
5. **Water finish.** Use the modeled bed and shore to establish depth, shallow
   margins and contact with stone. Then develop flow, surface response and
   localized edge effects, checking them from the actual walking camera.
6. **Runtime assembly and measured optimization.** Reuse meshes and materials,
   keep clean exports and simple colliders throughout authoring. On the assembled
   section, measure geometry, draw calls, foliage transparency, memory and
   loading before choosing instancing, visibility and LOD changes. Native and
   browser results are separate. Early traversal/import checks support the
   model work; full visual/performance acceptance follows assembly.
7. **Lighting and atmosphere.** After the preceding passes read coherently,
   develop daylight/evening, canopy shadows, depth haze, sunbeams and restrained
   ambient particles. Recheck performance after these effects are added.

A proposed recognizable composition is a spreading tree above the old ferry
steps, with the bank frontage behind it and a shaded market entrance visible
along the route. This expresses the existing settlement history without adding
a new plot or changing service rules. Preserve anchor masters and unit IDs.

For the final lighting pass, target warm sun, cooler readable shadows, dappled
canopy light, modest depth haze and localized sunbeams. Review the same materials
under the existing daylight and evening presets. Godot's built-in volumetric fog
requires Forward+, while its web export uses Compatibility. Prototype restrained
mesh-based light shafts for that baseline and evaluate them from inside, behind
and across the beam; opacity, intersections and occlusion need review. Native
volumetrics can be a separate quality option. These are proposed techniques,
not a verified shader or performance result. [Godot fog documentation](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html),
[web rendering support](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

The first deliverable is a derivative **clay layout/model study** and an optional
Godot traversal check under plain work lighting. Review the neighborhood above
and the landing, bank frontage and market threshold at eye level. Check usable
routes, building forms, continuous ground and purposeful gaps before dressing.
The later completed section adds materials, planting, detail, water and lighting;
review it with rays enabled and disabled. Evaluate the model pass with medium
third-person views as well as ground and layout checks. The static Blender
cameras do not establish a working Godot follow camera. Implementation and
verification are recorded separately in the current-state page.

### Reusable materials and assets

- **Poly Haven CC0, selectively sourced.** Ready-made CC0 materials from Poly Haven are permitted as *ingredients* — picked per surface family (stone, plaster, timber, tile, asphalt, soil) to fill realism gaps that hand-authored materials would bloat.
- **Harmonized, never collaged.** Every sourced material is adjusted (palette-mapped, scale-normalized, bump/style-tuned) to sit inside the shared lighting response of section 6. A mismatched photoreal asset collage — one PBR-scanned surface against a stylized neighbor — is the explicit rejection case.
- **Licensing hygiene:** every borrowed material and model is recorded with source URL, author credit, and license (CC0 verified) in the asset manifest before it enters a kit. No exceptions for "temp" assets that ship.
- **Reuse rules for kit pieces:**
  1. Architecture belongs to a named construction family and follows its connection dimensions. Shared botanical, stone, utility and street-furniture libraries can be reused across districts. Individual hero assets are allowed where they earn their silhouette and gameplay role; a single rigid lot grid is not mandatory.
  2. A kit ships with variants (wear states, sub-part swaps) so repetition reads as time, not as a copy-paste failure — and the variants remain the same net identity for stable housing (section 4). Cosmetic variation (planters, signage, wear seeds) restyles a facade; it never changes the underlying unit identity, which per [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md) is stable and independent of cosmetic generation.
  3. Collision and walkability (stairs, ramps, kerbs) authored with the art, not retrofitted.
  4. Chunks are **render/load units only.** Build kits and districts are authored independently of chunk boundaries; nothing artistic, economic, or ownership-related is defined at chunk scale.
- **Authoring pipeline:** geometry is authored or curated in Blender, then derived into runtime assets through the [3D frontend contract](../specs/frontend/3D_Frontend_Production.md). Authorized Godot prototypes can accompany Blender review. Production acceptance requires visual review of both the Blender source and the runtime asset under the same intended daylight/evening conditions in-browser.

---

## 9. Production Gates (Order Fixed)

Gates are production acceptance dependencies. Independent botanical/model studies,
playable blockouts and explicitly authorized imports can develop before approval.
They remain prototypes until their relevant art and runtime checks pass; preserve
source masters and stable world identities throughout.

| # | Gate | Deliverable | Pass condition |
|---|---|---|---|
| **G1** | Masterplan | River-and-rail macro layout (section 2–3) drawn as an authored plan: districts, water, rail, freight spur, the beginner loop corridor | Geography and district purposes approved; choke points and landmarks placed |
| **G2** | Kit samples | Founders' Quay waterfront, Cedar craft/courtyard and Eastgate station-side samples — grey + dressed, shared lighting and contemporary material language | Distinct silhouettes and useful premises; no generic reskinned boxes or forced remake of retained anchors |
| **G3** | Reference tree sample | Bank-derived green/cherry candidates with full canopies and connected branches, evaluated alongside praised Godot trees | Silhouette, leaf/clump depth and branch structure pass review; runtime version retains character |
| **G4** | Shared daylight/evening | The two global lighting presets applied identically across G2–G3 outputs | Color and contrast read vibrant with soft contrast in both; no washed fog, no clipped grade |
| **G5** | Connected start | Shared starter neighborhood with housing, market/work, bank, food and learning/recovery approaches; real terrain joins, stairs and ramps | Multiple usable routes support the choice milestone; actual controller traverses joins without hidden fixes |
| **G6** | Approval | Consolidated review pack of G1–G5 and relevant runtime captures | Founder review for finished art, with prototype imports clearly distinguished from approved production kits |

**Failure at any gate returns the pipeline to that gate only** — approved earlier gates stay approved unless the failure invalidates them, and extensions after G6 must not move existing homes (section 4, stable-unit rule).

---

## 10. What This Document Deliberately Does Not Say

- **No performance budget numbers.** Frame time, poly ceilings, and texture budgets belong to the browser production spec and must be measured on target hardware — the experimental build's frame rate is not a reference point.
- **No claim that anything works in-engine.** The 9x9x48 map is an experimental streaming attempt, not proof that the current integration works. It is not the final map, and its chunk grid is not a design commitment.
- **Camera direction versus implementation.** The founder requested medium third-person on 13 October. Control, obstruction and browser acceptance belong to the production spec; a reference view is not an implemented player camera.
- **No full-sim/every-district-complete promise.** The current neighborhood implements a tested subset of the full city. Event-specific demonstration cuts do not determine the full-game milestone.

---

## References

- [01_Game_Overview.md](01_Game_Overview.md) — vision, pillars, platform stance
- [11_Canonical_Game_Rules.md](11_Canonical_Game_Rules.md) — ownership, leases, resource stocks, stable IDs, chunk-vs-district rules
- [../specs/frontend/3D_Frontend_Production.md](../specs/frontend/3D_Frontend_Production.md) — browser delivery, LOD, and performance acceptance
- `game/World/city_plan.json` — experimental load-type probe (not the final masterplan)
