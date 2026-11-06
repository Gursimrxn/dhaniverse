class_name VHSky
extends RefCounted
## The reference sky (atmosphere.ts skyBase + clouds, env pass) on the CPU, projected to L2 spherical
## harmonics. Shaders evaluate it as the diffuse sky light: three.js
## IBL irradiance = env(normal, roughness 1) x intensity x albedo.
## The colours come from a time-of-day look (SkyModes, keyed like the shader globals); without one it
## is the reference's evening, which is also what the project's global defaults hold.

const EVENING := {
	"vh_sky_zenith": Vector3(0.205, 0.215, 0.40),
	"vh_sky_upper": Vector3(0.39, 0.37, 0.60),
	"vh_sky_mid_sun": Vector3(0.95, 0.56, 0.54),
	"vh_sky_mid_away": Vector3(0.55, 0.46, 0.64),
	"vh_sky_hor_sun": Vector3(1.42, 0.86, 0.58),
	"vh_sky_hor_away": Vector3(0.74, 0.60, 0.70),
	"vh_sky_halo": Vector3(1.0, 0.6, 0.34),
	"vh_sky_ground": Vector3(0.045, 0.055, 0.032),
	"vh_sky_glow": Vector3.ZERO,
	"vh_glow_dir": Vector2(0, -1),
	"vh_sun_core": Vector4(1.0, 0.62, 0.32, 3.0),
	"vh_cloud_lit": Vector3(1.25, 0.66, 0.56),
	"vh_cloud_lit_sun": Vector3(1.65, 1.02, 0.66),
	"vh_cloud_shade": Vector3(0.52, 0.43, 0.6),
	"vh_cloud_glow": Vector3(1.2, 0.7, 0.35),
	"vh_cloud_cover": 0.78,
}

static func _ss(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _k(look: Dictionary, key: String):
	return look[key] if look.has(key) else EVENING[key]

static func sky(d: Vector3, sun: Vector3, look := EVENING) -> Vector3:
	var y := maxf(d.y, 0.0)
	var sh := Vector2(sun.x, sun.z).normalized()
	var dh := (Vector2(d.x, d.z) + Vector2(1e-5, 1e-5)).normalized()
	var az := clampf(dh.dot(sh) * 0.5 + 0.5, 0.0, 1.0)
	var hor: Vector3 = (_k(look, "vh_sky_hor_away") as Vector3).lerp(_k(look, "vh_sky_hor_sun"), pow(az, 3.5))
	var mid: Vector3 = (_k(look, "vh_sky_mid_away") as Vector3).lerp(_k(look, "vh_sky_mid_sun"), pow(az, 2.2))
	var c := hor.lerp(mid, _ss(0.0, 0.14, y))
	c = c.lerp(_k(look, "vh_sky_upper"), _ss(0.08, 0.5, y))
	c = c.lerp(_k(look, "vh_sky_zenith"), _ss(0.4, 1.0, y))
	var sd := maxf(d.dot(sun), 0.0)
	c += (_k(look, "vh_sky_halo") as Vector3) * (pow(sd, 5.0) * 0.32 + pow(sd, 32.0) * 0.55)
	var glow: Vector3 = _k(look, "vh_sky_glow")
	if glow != Vector3.ZERO:
		c += glow * pow(maxf(dh.dot(_k(look, "vh_glow_dir")), 0.0), 6.0) * exp(-y * 9.0)
	return c

## Env-pass radiance (atmosphere.ts SKY_FRAG with ENV_PASS, uTime 0): dark ground below the horizon,
## sky + the sun's soft core + the painterly clouds above. Cloud banks sit relative to the sun's azimuth.
static func env(d: Vector3, sun: Vector3, look := EVENING) -> Vector3:
	if d.y < 0.0:
		return (sky(Vector3(d.x, 0.0, d.z), sun, look) * 0.55).lerp(_k(look, "vh_sky_ground"), _ss(0.0, 0.3, -d.y))
	var core: Vector4 = _k(look, "vh_sun_core")
	var col := sky(d, sun, look) + Vector3(core.x, core.y, core.z) * pow(maxf(d.dot(sun), 0.0), 400.0) * core.w
	if d.y > 0.01:
		var c := _clouds(d, sun, look)
		col = col.lerp(Vector3(c.x, c.y, c.z), c.w)
	return col

static func _hash12(p: Vector2) -> float:
	var p3 := Vector3(fposmod(p.x * 0.1031, 1.0), fposmod(p.y * 0.1031, 1.0), fposmod(p.x * 0.1031, 1.0))
	p3 += Vector3.ONE * p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3.ONE * 33.33)
	return fposmod((p3.x + p3.y) * p3.z, 1.0)

static func _vnoise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	return lerpf(lerpf(_hash12(i), _hash12(i + Vector2(1, 0)), u.x), lerpf(_hash12(i + Vector2(0, 1)), _hash12(i + Vector2(1, 1)), u.x), u.y)

static func _fbm5(p: Vector2) -> float:
	var s := 0.0
	var a := 0.5
	for i in 5:
		s += a * _vnoise(p)
		p = Vector2(1.6 * p.x - 1.2 * p.y, 1.2 * p.x + 1.6 * p.y)  # GLSL mat2(1.6, 1.2, -1.2, 1.6) * p
		a *= 0.5
	return s

static func _clouds(d: Vector3, sun: Vector3, look := EVENING) -> Vector4:
	var uv := Vector2(d.x, d.z) / (d.y + 0.07) * 0.55
	var n := _fbm5(uv * 1.6 + Vector2(3.1, 1.7))
	var az := wrapf(atan2(d.x, -d.z) - (atan2(sun.x, -sun.z) - 0.1309), -PI, PI)
	var bank := exp(-pow(absf((az + 0.30) / 0.38), 2.0)) * _ss(0.05, 0.12, d.y) * (1.0 - _ss(0.26, 0.42, d.y))
	var bank2 := exp(-pow(absf((az + 0.78) / 0.25), 2.0)) * _ss(0.08, 0.16, d.y) * (1.0 - _ss(0.24, 0.34, d.y))
	var wisp := exp(-pow(absf((az - 0.60) / 0.30), 2.0)) * _ss(0.10, 0.16, d.y) * (1.0 - _ss(0.26, 0.38, d.y))
	var high := _ss(0.35, 0.6, d.y) * 0.25
	var cov: float = float(_k(look, "vh_cloud_cover")) - bank * 0.36 - bank2 * 0.22 - wisp * 0.2 - high * 0.2
	var dens := _ss(cov, cov + 0.2, n)
	var to_sun := Vector2(sun.x, sun.z).normalized() * 0.08
	var n2 := _fbm5((uv + to_sun) * 1.6 + Vector2(3.1, 1.7))
	var lit := clampf(0.55 + (n - n2) * 5.0, 0.0, 1.0)
	var sd := maxf(d.dot(sun), 0.0)
	var lit_col: Vector3 = (_k(look, "vh_cloud_lit") as Vector3).lerp(_k(look, "vh_cloud_lit_sun"), pow(sd, 4.0))
	var cc: Vector3 = (_k(look, "vh_cloud_shade") as Vector3).lerp(lit_col, lit * (0.55 + 0.45 * (1.0 - _ss(0.1, 0.4, d.y))))
	cc += (_k(look, "vh_cloud_glow") as Vector3) * pow(sd, 10.0) * (1.0 - dens) * 1.6
	return Vector4(cc.x, cc.y, cc.z, dens * _ss(0.02, 0.1, d.y) * 0.92)

## SH coefficients of the env blurred like PMREM's roughness-1 level (a spherical Gaussian, sigma 0.582
## rad), which three.js samples as diffuse irradiance / PI. Returns the nine values for vh_sh0..8.
static func project(sun: Vector3, look := EVENING) -> Array:
	var c: Array = []
	for i in 9: c.append(Vector3.ZERO)
	var nu := 48
	var nphi := 96
	var w := 4.0 * PI / (nu * nphi)
	for i in nu:
		var u := -1.0 + (i + 0.5) * 2.0 / nu
		var r := sqrt(1.0 - u * u)
		for j in nphi:
			var phi := (j + 0.5) * TAU / nphi
			var d := Vector3(r * cos(phi), u, r * sin(phi))
			var L := env(d, sun, look) * w
			var b := _basis(d)
			for k in 9: c[k] += L * b[k]
	# Gaussian blur in SH: band l scaled by exp(-l(l+1) sigma^2 / 2)
	var g1 := exp(-0.582 * 0.582)
	var g2 := exp(-3.0 * 0.582 * 0.582)
	var a := [1.0, g1, g1, g1, g2, g2, g2, g2, g2]
	for k in 9: c[k] *= a[k]
	return c

static func set_coeffs(c: Array) -> void:
	for k in 9: RenderingServer.global_shader_parameter_set("vh_sh%d" % k, c[k])

## Sets global shader params vh_sh0..8 for this sun and look.
static func upload(sun: Vector3, look := EVENING) -> void:
	set_coeffs(project(sun, look))

static func _basis(d: Vector3) -> Array:
	return [0.282095, 0.488603 * d.y, 0.488603 * d.z, 0.488603 * d.x, 1.092548 * d.x * d.y, 1.092548 * d.y * d.z,
		0.315392 * (3.0 * d.z * d.z - 1.0), 1.092548 * d.x * d.z, 0.546274 * (d.x * d.x - d.y * d.y)]
