class_name MapData
extends RefCounted
## The starter quarter "Founders' Quay": layout data + terrain sampling.
## Godot axes: +X east, -Z north, metres. Plaza centre is the origin.
## Scalability: each district is a separate entry in DISTRICTS; future ones are
## visible but gated by an in-world reason, never by an invisible wall.

const X0 := -130.0
const Z0 := -120.0
const W := 260.0
const D := 240.0
const RES := 1.0                      # metres per terrain cell
const WATER := -0.6
const TOWN_Y := 0.35                  # plaza / building plinth height

# River comes from the northern catchment, bends past the quay, leaves south-west.
const RIVER := [
	Vector2(-60, -130), Vector2(-62, -80), Vector2(-56, -40), Vector2(-50, -10),
	Vector2(-52, 20), Vector2(-64, 55), Vector2(-90, 85), Vector2(-120, 105), Vector2(-150, 112)]
const RIVER_HALF := 9.0

# Paved lanes: [points, half width]
const PATHS := [
	[[Vector2(-38, 0), Vector2(-4, 0)], 2.2],                                    # quay → plaza axis
	[[Vector2(-4, 46), Vector2(-4, 14)], 2.0],                                   # arrival lane from the south
	[[Vector2(-4, -12), Vector2(-14, -20)], 2.0],                                # plaza → bank steps
	[[Vector2(6, 2), Vector2(16, -2)], 2.2],                                     # plaza → market
	[[Vector2(8, 12), Vector2(18, 22), Vector2(30, 26)], 1.8],                   # → common table
	[[Vector2(30, 26), Vector2(44, 30), Vector2(52, 24)], 1.6],                  # → housing court
	[[Vector2(34, 10), Vector2(46, 4), Vector2(70, 0), Vector2(98, -2)], 1.8],   # east lane → station (gated)
	[[Vector2(-40, -14), Vector2(-42, -40), Vector2(-46, -70)], 1.4],            # riverwalk north
	[[Vector2(-40, 14), Vector2(-48, 40), Vector2(-62, 64)], 1.4],               # riverwalk south
	[[Vector2(8, -14), Vector2(14, -40), Vector2(22, -62)], 1.6],                # learning terrace (gated)
	[[Vector2(-44, -34), Vector2(-68, -34)], 1.8],                               # bridge (under repair)
]

# Plazas: centre, half size, corner radius
const PLAZAS := [
	[Vector2(-14, 0), Vector2(22, 13), 6.0],     # Quay Square
	[Vector2(48, 32), Vector2(9, 7), 3.0],       # housing court
]

# Approved building masters. face = direction the front door looks at.
const SITES := [
	{"id": "dv02", "glb": "dv02_bank.glb", "name": "Bank", "pos": Vector2(-16, -28), "face": Vector2(0, 1), "role": "bank"},
	{"id": "dv03", "glb": "dv03_market.glb", "name": "Market Hall", "pos": Vector2(30, -6), "face": Vector2(-1, 0), "role": "market"},
	{"id": "dv01", "glb": "dv01_arrival.glb", "name": "Arrival Hall", "pos": Vector2(-24, 26), "face": Vector2(0, -1), "role": "arrival"},
	{"id": "dv04", "glb": "dv04_common_table.glb", "name": "Common Table", "pos": Vector2(18, 38), "face": Vector2(-0.5, -1), "role": "food"},
	{"id": "dv05", "glb": "dv05_housing.glb", "name": "Quay Court Homes", "pos": Vector2(64, 40), "face": Vector2(-1, 0), "role": "home"},
]

const SPAWN := Vector3(-4, 1.0, 44)

# Districts beyond the starter quarter: shown, named, gated with a reason.
const DISTRICTS := [
	{"name": "Eastgate Station", "gate": Vector2(96, -2), "reason": "Platform works — opening soon"},
	{"name": "Learning Terrace", "gate": Vector2(22, -62), "reason": "Library steps being rebuilt"},
	{"name": "Cedar Quarter", "gate": Vector2(-68, -34), "reason": "Bridge repairs in progress"},
]

# --- sampling -----------------------------------------------------------------
static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func poly_dist(p: Vector2, pts: Array) -> float:
	var best := 1e9
	for i in pts.size() - 1:
		best = minf(best, _seg_dist(p, pts[i], pts[i + 1]))
	return best

static func plaza_dist(p: Vector2, pl: Array) -> float:
	# signed distance to a rounded rectangle (negative inside)
	var q: Vector2 = (p - pl[0]).abs() - pl[1] + Vector2(pl[2], pl[2])
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - pl[2]

static func noise2(p: Vector2) -> float:
	return sin(p.x * 0.031 + 1.7) * cos(p.y * 0.027 - 0.4) * 0.5 + sin(p.x * 0.083 + p.y * 0.061) * 0.25

## Returns [height, path, bank, plaza, soil] for a world point.
static func sample(p: Vector2, sites_ext: Array) -> Array:
	var river_d := poly_dist(p, RIVER)
	# rolling land, rising into wooded hills at the edges
	var edge := maxf(absf(p.x - 0) - 85.0, 0.0) * 0.12 + maxf(-p.y - 70.0, 0.0) * 0.14 + maxf(p.y - 80.0, 0.0) * 0.1
	var h := 0.6 + noise2(p) * 1.6 + edge * edge * 0.15 + edge
	# across the river the land climbs (Cedar Quarter bank)
	if p.x < -60.0: h += clampf((-60.0 - p.x) * 0.06, 0.0, 3.0)
	# river channel with a shallow shelf
	var bed := WATER - 2.4 + smoothstep(0.0, RIVER_HALF, river_d) * 1.4
	var bank_t := smoothstep(RIVER_HALF + 7.0, RIVER_HALF - 1.0, river_d)
	h = lerpf(h, minf(h, bed), bank_t)
	var bank := smoothstep(RIVER_HALF + 5.0, RIVER_HALF + 1.0, river_d)

	var path := 0.0
	for pa in PATHS:
		path = maxf(path, smoothstep(pa[1] + 0.8, pa[1] - 0.4, poly_dist(p, pa[0])))
	var plaza := 0.0
	var flat := 0.0
	for pl in PLAZAS:
		var sd := plaza_dist(p, pl)
		plaza = maxf(plaza, smoothstep(0.8, -0.6, sd))
		flat = maxf(flat, smoothstep(10.0, 0.0, sd))
	var soil := 0.0
	for s in sites_ext:
		var q: Vector2 = (p - s.center).abs() - s.half
		var sd2 := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
		flat = maxf(flat, smoothstep(9.0, 1.0, sd2))
		soil = maxf(soil, smoothstep(3.5, 1.5, sd2) * (1.0 - smoothstep(1.5, 0.5, sd2)) * 0.6)
	flat = maxf(flat, path * 0.85)
	h = lerpf(h, TOWN_Y, flat * (1.0 - bank_t * 0.6))
	# quay edge: plaza stays high right up to the quay wall
	return [h, path, bank * (1.0 - plaza), plaza, soil]
