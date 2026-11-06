class_name SkyModes
extends RefCounted
## Time-of-day looks for the valley: day, the reference evening, night. A look holds everything the
## vh shaders read for sky, atmosphere and artificial light (keys named after their shader globals),
## the grade, the distant city's tint and how strongly the lamps light the town. world.json places
## the sun (or moon) and sets its colour and intensity per mode; world.gd fills those in, adds the
## sky's SH and blends two looks key by key while the mode changes.
## Colours are linear HDR, as the shaders use them.

const ORDER := ["day", "evening", "night"]
const LABELS := {"day": "Day", "evening": "Evening", "night": "Night"}

const LOOKS := {
	# Clear, sunny midday: deep blue zenith, bright pale horizon, white sun with a tight halo, fair-weather
	# cumulus and their shadows drifting over the valley, crisp air, beams through the crowns.
	"day": {
		"vh_sky_zenith": Vector3(0.075, 0.18, 0.47),
		"vh_sky_upper": Vector3(0.16, 0.31, 0.66),
		"vh_sky_mid_sun": Vector3(0.44, 0.58, 0.84),
		"vh_sky_mid_away": Vector3(0.31, 0.46, 0.76),
		"vh_sky_hor_sun": Vector3(0.94, 0.95, 0.96),
		"vh_sky_hor_away": Vector3(0.64, 0.73, 0.88),
		"vh_sky_halo": Vector3(0.9, 0.82, 0.66),
		"vh_sky_ground": Vector3(0.07, 0.08, 0.05),
		"vh_sky_glow": Vector3.ZERO,
		"vh_sun_core": Vector4(1.0, 0.94, 0.82, 4.0),
		"vh_sun_disc": Vector4(1.0, 0.97, 0.92, 70.0),
		"vh_cloud_lit": Vector3(1.3, 1.34, 1.42),
		"vh_cloud_lit_sun": Vector3(1.85, 1.8, 1.7),
		"vh_cloud_shade": Vector3(0.56, 0.63, 0.78),
		"vh_cloud_glow": Vector3(0.8, 0.75, 0.6),
		"vh_cloud_cover": 0.84,
		"vh_hemi_sky": Vector3(0.14, 0.18, 0.26),
		"vh_hemi_ground": Vector3(0.05, 0.05, 0.03),
		"vh_bounce": Vector3(0.2, 0.18, 0.14),
		"vh_fog_k": Vector4(0.00015, 0.0016, 0.095, 0.8),
		"vh_night": 0.0,
		"vh_glow": Vector4(0.0, 0.0, 0.0, 0.0),
		"vh_unlit": Vector3(1.15, 1.15, 1.15),
		"vh_sun_spec": Vector3(4.6, 4.4, 4.0),
		"vh_cloud_shadow": Vector4(0.5, 0.0011, 0.56, 4.0),
		"vh_shafts": Vector4(0.5, 0.45, 0.35, 0.0),
		"vh_lamp_fade": Vector4(28.0, 40.0, 0.0, 0.0),
		"lamps": 0.0,
		"city_body": Vector3(0.55, 0.62, 0.78),
		"city_sun": Vector3(1.15, 1.08, 0.98),
		"grade": {
			"exposure": 0.88, "bloom_strength": 0.07, "bloom_threshold": 1.9, "vignette": 0.12,
			"lift": Vector3(0.0, 0.003, 0.01), "gain": Vector3(0.016, 0.008, -0.006), "curve": 0.12,
			"saturation": 1.03, "shadow_sat": 0.98, "white": Vector3(1.0, 1.0, 1.0),
			"rays": 0.18, "ray_threshold": 1.7, "ray_tint": Vector3(1.0, 0.96, 0.88),
		},
	},
	# The reference's golden evening (atmosphere.ts / Game.ts), as the project's globals default to;
	# signs and windows are just coming on.
	# The opening: the morning the ferry comes in, cooler and pinker than the evening. Not one of T's times of day.
	"dawn": {
		"vh_sky_zenith": Vector3(0.11, 0.17, 0.4),
		"vh_sky_upper": Vector3(0.26, 0.33, 0.58),
		"vh_sky_mid_sun": Vector3(0.98, 0.68, 0.62),
		"vh_sky_mid_away": Vector3(0.42, 0.47, 0.68),
		"vh_sky_hor_sun": Vector3(1.5, 1.0, 0.72),
		"vh_sky_hor_away": Vector3(0.62, 0.62, 0.76),
		"vh_sky_halo": Vector3(1.0, 0.7, 0.5),
		"vh_sky_ground": Vector3(0.045, 0.055, 0.032),
		"vh_sky_glow": Vector3.ZERO,
		"vh_sun_core": Vector4(1.0, 0.7, 0.45, 3.0),
		"vh_sun_disc": Vector4(1.0, 0.9, 0.74, 45.0),
		"vh_cloud_lit": Vector3(1.2, 0.76, 0.74),
		"vh_cloud_lit_sun": Vector3(1.6, 1.12, 0.86),
		"vh_cloud_shade": Vector3(0.5, 0.48, 0.66),
		"vh_cloud_glow": Vector3(1.2, 0.7, 0.35),
		"vh_cloud_cover": 0.78,
		"vh_hemi_sky": Vector3(0.12, 0.13, 0.2),
		"vh_hemi_ground": Vector3(0.01855, 0.017125, 0.008275),
		"vh_bounce": Vector3(0.11, 0.066, 0.037),
		"vh_fog_k": Vector4(0.00016, 0.0021, 0.095, 0.75),
		"vh_night": 0.0,
		"vh_glow": Vector4(1.0, 0.12, 0.15, 0.0),
		"vh_unlit": Vector3(1.0, 1.0, 1.0),
		"vh_sun_spec": Vector3(2.6, 1.768, 1.092),
		"vh_cloud_shadow": Vector4(0.0, 0.0011, 0.56, 4.0),
		"vh_shafts": Vector4(0.3, 0.22, 0.14, 0.0),
		"vh_lamp_fade": Vector4(28.0, 40.0, 0.0, 0.0),
		"lamps": 0.0,
		"city_body": Vector3(0.5, 0.52, 0.7),
		"city_sun": Vector3(1.25, 0.8, 0.6),
		"grade": {
			"exposure": 1.0, "bloom_strength": 0.12, "bloom_threshold": 1.4, "vignette": 0.18,
			"lift": Vector3(0.006, 0.0, 0.018), "gain": Vector3(0.02, 0.008, -0.012), "curve": 0.1,
			"saturation": 1.0, "shadow_sat": 1.0, "white": Vector3(1.0, 1.0, 1.0),
			"rays": 0.16, "ray_threshold": 1.8, "ray_tint": Vector3(1.0, 0.85, 0.65),
		},
	},
	"evening": {
		"vh_sky_zenith": Vector3(0.14, 0.17, 0.36),
		"vh_sky_upper": Vector3(0.29, 0.31, 0.52),
		"vh_sky_mid_sun": Vector3(1.0, 0.63, 0.47),
		"vh_sky_mid_away": Vector3(0.45, 0.44, 0.6),
		"vh_sky_hor_sun": Vector3(1.55, 0.95, 0.56),
		"vh_sky_hor_away": Vector3(0.62, 0.58, 0.69),
		"vh_sky_halo": Vector3(1.0, 0.6, 0.34),
		"vh_sky_ground": Vector3(0.045, 0.055, 0.032),
		"vh_sky_glow": Vector3.ZERO,
		"vh_sun_core": Vector4(1.0, 0.62, 0.32, 3.0),
		"vh_sun_disc": Vector4(1.0, 0.86, 0.62, 45.0),
		"vh_cloud_lit": Vector3(1.25, 0.66, 0.56),
		"vh_cloud_lit_sun": Vector3(1.65, 1.02, 0.66),
		"vh_cloud_shade": Vector3(0.52, 0.43, 0.6),
		"vh_cloud_glow": Vector3(1.2, 0.7, 0.35),
		"vh_cloud_cover": 0.78,
		"vh_hemi_sky": Vector3(0.121275, 0.1127, 0.178925),
		"vh_hemi_ground": Vector3(0.01855, 0.017125, 0.008275),
		"vh_bounce": Vector3(0.11, 0.066, 0.037),
		"vh_fog_k": Vector4(0.00016, 0.0021, 0.095, 0.75),
		"vh_night": 0.0,
		"vh_glow": Vector4(1.0, 0.12, 0.15, 0.0),
		"vh_unlit": Vector3(1.0, 1.0, 1.0),
		"vh_sun_spec": Vector3(2.6, 1.768, 1.092),
		"vh_cloud_shadow": Vector4(0.0, 0.0011, 0.56, 4.0),
		"vh_shafts": Vector4(0.34, 0.2, 0.09, 0.0),
		"vh_lamp_fade": Vector4(28.0, 40.0, 0.0, 0.0),
		"lamps": 0.0,
		"city_body": Vector3(0.5, 0.52, 0.7),
		"city_sun": Vector3(1.25, 0.8, 0.6),
		"grade": {
			"exposure": 1.0, "bloom_strength": 0.12, "bloom_threshold": 1.4, "vignette": 0.18,
			"lift": Vector3(0.006, 0.0, 0.018), "gain": Vector3(0.02, 0.008, -0.012), "curve": 0.1,
			"saturation": 1.0, "shadow_sat": 1.0, "white": Vector3(1.0, 1.0, 1.0),
			"rays": 0.16, "ray_threshold": 1.8, "ray_tint": Vector3(1.0, 0.85, 0.65),
		},
	},
	# Moonlit night: navy sky with stars and the Milky Way, a light dome over the capital, cool moonlight
	# and blue shade (greyed by night vision), mist in the valley; street lamps, bollards and doorways
	# light the town warm, windows glow low, signs and building names are lit.
	"night": {
		"vh_sky_zenith": Vector3(0.003, 0.0048, 0.014),
		"vh_sky_upper": Vector3(0.0048, 0.0078, 0.022),
		"vh_sky_mid_sun": Vector3(0.016, 0.022, 0.048),
		"vh_sky_mid_away": Vector3(0.008, 0.012, 0.028),
		"vh_sky_hor_sun": Vector3(0.03, 0.04, 0.072),
		"vh_sky_hor_away": Vector3(0.018, 0.024, 0.046),
		"vh_sky_halo": Vector3(0.1, 0.12, 0.18),
		"vh_sky_ground": Vector3(0.004, 0.005, 0.006),
		"vh_sky_glow": Vector3(0.07, 0.042, 0.022),
		"vh_sun_core": Vector4(0.5, 0.58, 0.8, 0.6),
		"vh_sun_disc": Vector4(0.0, 0.0, 0.0, 0.0),
		"vh_cloud_lit": Vector3(0.035, 0.042, 0.065),
		"vh_cloud_lit_sun": Vector3(0.12, 0.135, 0.18),
		"vh_cloud_shade": Vector3(0.01, 0.012, 0.02),
		"vh_cloud_glow": Vector3(0.1, 0.11, 0.16),
		"vh_cloud_cover": 0.8,
		"vh_hemi_sky": Vector3(0.034, 0.048, 0.088),
		"vh_hemi_ground": Vector3(0.004, 0.004, 0.005),
		"vh_bounce": Vector3(0.006, 0.007, 0.01),
		"vh_fog_k": Vector4(0.0003, 0.0062, 0.095, 0.75),
		"vh_night": 1.0,
		"vh_glow": Vector4(1.0, 1.0, 1.0, 1.0),
		"vh_unlit": Vector3(0.05, 0.06, 0.1),
		"vh_sun_spec": Vector3(0.45, 0.55, 0.8),
		"vh_cloud_shadow": Vector4(0.3, 0.0011, 0.6, 3.0),
		"vh_shafts": Vector4(0.0, 0.0, 0.0, 0.0),
		"vh_lamp_fade": Vector4(28.0, 40.0, 1.0, 0.0),
		"lamps": 1.0,
		"city_body": Vector3(0.2, 0.21, 0.28),
		"city_sun": Vector3(0.3, 0.35, 0.5),
		"grade": {
			"exposure": 1.9, "bloom_strength": 0.25, "bloom_threshold": 1.1, "vignette": 0.32,
			"lift": Vector3(0.0, 0.006, 0.02), "gain": Vector3(0.01, 0.003, -0.008), "curve": 0.12,
			"saturation": 0.95, "shadow_sat": 0.55, "white": Vector3(0.94, 0.98, 1.08),
			"rays": 0.0, "ray_threshold": 1.6, "ray_tint": Vector3(1.0, 1.0, 1.0),
		},
	},
}

## Key-by-key blend of two looks (floats, vectors, colours, the SH array, the nested grade).
static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a:
		var x = a[k]
		var y = b.get(k, x)
		match typeof(x):
			TYPE_FLOAT, TYPE_INT:
				out[k] = lerpf(x, y, t)
			TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR:
				out[k] = x.lerp(y, t)
			TYPE_ARRAY:
				var arr: Array = []
				for i in x.size(): arr.append(x[i].lerp(y[i], t))
				out[k] = arr
			TYPE_DICTIONARY:
				out[k] = mix(x, y, t)
			_:
				out[k] = y if t >= 0.5 else x
	return out
