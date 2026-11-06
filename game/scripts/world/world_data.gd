class_name WorldData
extends RefCounted
## The composed valley (world/valley/world.json + layers from tools/compose_valley.py).
## Layers live once as GPU textures (terrain, water, ground-cover fields) and once as
## CPU arrays for placement. Nothing about the layout lives in code.

var d: Dictionary
var x0: float
var z0: float
var w: float
var dep: float
var res: float
var nx: int
var nz: int
var field := PackedFloat32Array()     # per cell: height, water signed distance, water level, paving distance
var cover := PackedByteArray()        # per cell: grass, fern, flower, tree density
var field_tex: ImageTexture
var cover_tex: ImageTexture
var paved_tex: ImageTexture
var field_rect: Vector4               # texel-centre aligned world rect of field/cover textures
var paved_rect: Vector4

static func load_file(path: String) -> WorldData:
	var wd := WorldData.new()
	wd.d = JSON.parse_string(FileAccess.get_file_as_string(path))
	var b: Dictionary = wd.d.bounds
	wd.x0 = b.x0; wd.z0 = b.z0; wd.w = b.w; wd.dep = b.d; wd.res = b.res
	var L: Dictionary = wd.d.layers
	wd.nx = int(L.nx); wd.nz = int(L.nz)
	var fimg := Image.create_from_data(wd.nx, wd.nz, false, Image.FORMAT_RGBAH, _gunzip(L.field, wd.nx * wd.nz * 8))
	wd.field_tex = ImageTexture.create_from_image(fimg)
	fimg.convert(Image.FORMAT_RGBAF)
	wd.field = fimg.get_data().to_float32_array()
	wd.cover = _gunzip(L.cover, wd.nx * wd.nz * 4)
	wd.cover_tex = ImageTexture.create_from_image(Image.create_from_data(wd.nx, wd.nz, false, Image.FORMAT_RGBA8, wd.cover))
	var pnx := int(L.pnx)
	var pnz := int(L.pnz)
	var pr := float(L.paved_res)
	wd.paved_tex = ImageTexture.create_from_image(Image.create_from_data(pnx, pnz, false, Image.FORMAT_L8, _gunzip(L.paved, pnx * pnz)))
	wd.field_rect = Vector4(wd.x0 - wd.res * 0.5, wd.z0 - wd.res * 0.5, wd.nx * wd.res, wd.nz * wd.res)
	wd.paved_rect = Vector4(wd.x0 - pr * 0.5, wd.z0 - pr * 0.5, pnx * pr, pnz * pr)
	return wd

static func _gunzip(path: String, size: int) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path).decompress(size, FileAccess.COMPRESSION_GZIP)

static func v2(a) -> Vector2: return Vector2(a[0], a[1])
static func v3(a) -> Vector3: return Vector3(a[0], a[1], a[2])

## Bilinear read of field channel k at a world point.
func _f(k: int, p: Vector2) -> float:
	var fx := clampf((p.x - x0) / res, 0.0, nx - 1.001)
	var fz := clampf((p.y - z0) / res, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var o := (iz * nx + ix) * 4 + k
	var a := lerpf(field[o], field[o + 4], fx - ix)
	var b := lerpf(field[o + nx * 4], field[o + nx * 4 + 4], fx - ix)
	return lerpf(a, b, fz - iz)

func height(p: Vector2) -> float: return _f(0, p)
func water_sd(p: Vector2) -> float: return _f(1, p)
func water_z(p: Vector2) -> float: return _f(2, p)
func pave_dist(p: Vector2) -> float: return _f(3, p)

## Nearest-cell cover density (0..1) for channel k: 0 grass, 1 fern, 2 flower, 3 tree.
func cover_at(k: int, p: Vector2) -> float:
	var ix := clampi(int(round((p.x - x0) / res)), 0, nx - 1)
	var iz := clampi(int(round((p.y - z0) / res)), 0, nz - 1)
	return cover[(iz * nx + ix) * 4 + k] / 255.0

func inside(p: Vector2, margin := 0.0) -> bool:
	return p.x > x0 + margin and p.x < x0 + w - margin and p.y > z0 + margin and p.y < z0 + dep - margin

static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)
