// Stylized Grass Shader — billboard, wind, fake perspective, character displacement, toon shading, cloud shadows
// Adapted from Dylearn's grass shader (MIT License)

shader_type spatial;
render_mode depth_prepass_alpha, cull_disabled;

#include "res://original/shaders/clouds.gdshaderinc"

global uniform vec3 wind_direction = vec3(0.0, 0.0, 1.0);
global uniform float wind_speed = 0.06;
global uniform float wind_strength = 1.0;

group_uniforms grass_colours;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform vec4 albedo1 : source_color = vec4(1.0);
uniform sampler2D albedo2_noise;
uniform vec4 albedo2 : source_color = vec4(1.0);
uniform float albedo2_scale : hint_range(0.0, 1.0, 0.001) = 0.11;
uniform float albedo2_threshold : hint_range(0.0, 1.0, 0.001) = 0.537;
uniform sampler2D albedo3_noise;
uniform vec4 albedo3 : source_color = vec4(1.0);
uniform float albedo3_scale : hint_range(0.0, 0.1, 0.001) = 0.1;
uniform float albedo3_threshold : hint_range(0.0, 1.0, 0.001) = 0.471;

group_uniforms accents;
uniform float accent_frequency1 : hint_range(0.0, 0.05, 0.0001) = 0.001;
uniform sampler2D accent_texture1 : source_color, filter_nearest;
uniform vec4 accent_albedo1 : source_color = vec4(1.0);
uniform float accent_height1 : hint_range(0.0, 1.0, 0.001) = 0.1;
uniform float accent_scale1 : hint_range(0.0, 2.0, 0.001) = 1.0;
uniform float accent_probability2 : hint_range(0.0, 0.05, 0.0001) = 0.0001;
uniform sampler2D accent_texture2 : source_color, filter_nearest;
uniform vec4 accent_albedo2 : source_color = vec4(1.0);
uniform float accent_height2 : hint_range(0.0, 1.0, 0.001) = 0.185;
uniform float accent_scale2 : hint_range(0.0, 2.0, 0.001) = 1.0;

group_uniforms wind_animation;
uniform float framerate : hint_range(1.0, 60.0) = 30.0;
uniform bool quantised = false;
uniform bool world_space_sway = true;
uniform float world_sway_angle : hint_range(0.0, 180.0) = 60.0;
uniform float fake_perspective_scale : hint_range(-0.15, 0.6, 0.001) = 0.3;
uniform sampler2D wind_noise;
uniform float wind_noise_threshold : hint_range(-1.0, 1.0, 0.001) = 0.2;
uniform float wind_noise_scale : hint_range(0.0, 0.1, 0.001) = 0.05;
uniform float noise_diverge_angle : hint_range(0.0, 45.0, 0.001) = 10.0;
uniform bool view_space_sway = true;
uniform float view_sway_speed : hint_range(0.0, 5.0) = 0.1;
uniform float view_sway_angle : hint_range(0.0, 45.0) = 10.0;

group_uniforms character_interaction;
uniform vec4 character_data[8];

group_uniforms toon_lighting;
uniform int cuts : hint_range(1, 8) = 3;
uniform float wrap : hint_range(-2.0, 2.0) = 0.0;
uniform float steepness : hint_range(1.0, 8.0) = 1.0;
uniform float threshold_gradient_size : hint_range(0.0, 1.0) = 0.5;
uniform float min_ambient : hint_range(0.0, 1.0) = 0.22;

varying float instance_id;
varying float id_seed1;
varying float id_seed2;
varying vec3 object_origin;
varying vec3 model_origin;
varying float wind_noise_sample;
varying float debug_wind;

float location_seed(vec2 location) {
	return fract(sin(dot(location, vec2(12.9898, 78.233))) * 43758.5453123);
}

float random_val(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

mat4 rotate_around_axis(vec3 axis, float angle) {
	axis = normalize(axis);
	float c = cos(angle);
	float s = sin(angle);
	float oc = 1.0 - c;
	return mat4(
		vec4(oc * axis.x * axis.x + c, oc * axis.x * axis.y - axis.z * s, oc * axis.z * axis.x + axis.y * s, 0.0),
		vec4(oc * axis.x * axis.y + axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z - axis.x * s, 0.0),
		vec4(oc * axis.z * axis.x - axis.y * s, oc * axis.y * axis.z + axis.x * s, oc * axis.z * axis.z + c, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

mat4 view_space_rotate(float angle) {
	return mat4(
		vec4(cos(angle), -sin(angle), 0.0, 0.0),
		vec4(sin(angle), cos(angle), 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void vertex() {
	instance_id = float(INSTANCE_ID);
	id_seed1 = random_val(instance_id);
	id_seed2 = random_val(instance_id + PI);

	// Accent grass
	if (id_seed1 < accent_frequency1) {
		VERTEX.y += accent_height1;
		VERTEX *= accent_scale1;
	} else if (id_seed2 < accent_probability2) {
		VERTEX.y += accent_height2;
		VERTEX *= accent_scale2;
	}

	object_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;

	// Character displacement: bend grass away from nearby characters.
	// Must happen BEFORE any wind rotation so the VERTEX is still in pure
	// model space where world-space axes match model-space axes.
	for (int i = 0; i < 8; i++) {
		vec4 cd = character_data[i];
		float radius = cd.w;
		if (radius <= 0.0) continue;

		vec3 delta = object_origin - cd.xyz;
		float dist_sq = delta.x * delta.x + delta.z * delta.z; // XZ distance only
		float radius_sq = radius * radius;

		if (dist_sq < radius_sq) {
			float strength = 1.0 - sqrt(dist_sq) / radius;
			strength = strength * strength;
			vec3 push_dir = (dist_sq > 0.0001)
				? normalize(vec3(delta.x, 0.0, delta.z))
				: vec3(0.0, 0.0, 1.0);
			vec3 axis = vec3(-push_dir.z, 0.0, push_dir.x);
			float angle = strength * 0.8727; // ~50 degrees max push in radians
			VERTEX = (rotate_around_axis(axis, angle) * vec4(VERTEX, 1.0)).xyz;
		}
	}

	float seed = 10.0 * location_seed(object_origin.xy);
	float frametime = 1.0 / framerate;
	float phase = mod(seed, frametime);

	float time = TIME;
	if (quantised) {
		time += phase;
		time = round(time * framerate) / framerate;
	}

	// Wind noise
	vec2 noise_dir1 = rotate_vec2(wind_direction.xz, noise_diverge_angle);
	vec2 noise_dir2 = rotate_vec2(wind_direction.xz, -noise_diverge_angle);
	vec2 noise_time1 = time * wind_speed * normalize(noise_dir1);
	vec2 noise_time2 = time * wind_speed * normalize(noise_dir2);

	float noise1 = texture(wind_noise, object_origin.xz * wind_noise_scale + noise_time1).r;
	float noise2 = texture(wind_noise, object_origin.xz * (wind_noise_scale * 0.8) + (noise_time2 * 0.89 * PI / 3.0)).r;
	wind_noise_sample = noise1 * noise2;
	wind_noise_sample = clamp(wind_noise_sample + wind_noise_threshold, 0.0, 1.0);
	wind_noise_sample = (wind_noise_sample - 0.5) * 2.0 * wind_strength;

	float world_sway = wind_noise_sample * radians(world_sway_angle);
	vec3 wind_world_axis = (vec4(noise_dir1.y, 0.0, -noise_dir1.x, 1.0) * INV_VIEW_MATRIX).xyz;
	mat4 world_rotation = rotate_around_axis(wind_world_axis, world_sway);

	float model_sway = sin((time + seed) * view_sway_speed * 2.0 * PI) * radians(view_sway_angle);
	mat4 model_rotation = view_space_rotate(model_sway);

	if (view_space_sway) {
		VERTEX = (model_rotation * vec4(VERTEX, 1.0)).xyz;
	}
	if (world_space_sway) {
		VERTEX = (world_rotation * vec4(VERTEX, 1.0)).xyz;
	}

	// Billboard to camera
	mat4 modified_model_view = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0),
		MODEL_MATRIX[3]
	);
	model_origin = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	MODELVIEW_MATRIX = modified_model_view;

	debug_wind = wind_noise_sample;
}

void fragment() {
	vec2 uv = UV;
	uv.x -= 0.5;
	float ws = wind_noise_sample * fake_perspective_scale;
	if (world_space_sway) {
		ws *= dot(CAMERA_DIRECTION_WORLD.xz, wind_direction.xz);
		uv.x *= (1.0 - uv.y) * ws + 1.0;
	}
	uv.x += 0.5;
	uv.x = clamp(uv.x, 0.0, 1.0);

	vec4 albedo_tex = texture(albedo_texture, uv);
	ALBEDO = albedo1.rgb * albedo_tex.rgb;

	float a2 = texture(albedo2_noise, object_origin.xz * albedo2_scale).r;
	float a3 = texture(albedo3_noise, object_origin.xz * albedo3_scale).r;
	if (a2 > albedo2_threshold) { ALBEDO = albedo2.rgb; }
	if (a3 > albedo3_threshold) { ALBEDO = albedo3.rgb; }

	if (id_seed1 < accent_frequency1) {
		albedo_tex = texture(accent_texture1, uv);
		ALBEDO = accent_albedo1.rgb * albedo_tex.rgb;
	} else if (id_seed2 < accent_probability2) {
		albedo_tex = texture(accent_texture2, uv);
		ALBEDO = accent_albedo2.rgb * albedo_tex.rgb;
	}

	LIGHT_VERTEX = model_origin;
	ALPHA = albedo_tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	float diffuse_amount = NdotL + (ATTENUATION - 1.0) + wrap;
	diffuse_amount *= steepness;

	if (LIGHT_IS_DIRECTIONAL) {
		vec3 vertex_world_pos = (INV_VIEW_MATRIX * vec4(model_origin, 1.0)).xyz;
		float cloud_shadow = get_cloud_shadow(vertex_world_pos);
		diffuse_amount = min(diffuse_amount, cloud_shadow);
	}

	float cuts_inv = 1.0 / float(cuts);
	float cut = cuts_inv;
	float original_index = ceil(diffuse_amount * float(cuts));
	float original_stepped = clamp(original_index * cut, 0.0, 1.0);
	float diffuse_stepped = clamp(diffuse_amount + mod(1.0 - diffuse_amount, cuts_inv), 0.0, 1.0);

	if (threshold_gradient_size > 0.0) {
		float nearest_k = floor(diffuse_amount / cut + 0.5);
		float threshold = nearest_k * cut;
		if (nearest_k >= 0.0 && nearest_k <= float(cuts)) {
			float halfWidth = 0.5 * cut * threshold_gradient_size;
			float low  = max(0.0, threshold - halfWidth);
			float high = min(1.0, threshold + halfWidth);
			float blend = (high > low) ? smoothstep(low, high, diffuse_amount) : step(threshold, diffuse_amount);
			float leftValue  = threshold;
			float rightValue = min(threshold + cut, 1.0);
			diffuse_stepped = clamp(mix(leftValue, rightValue, blend), 0.0, 1.0);
		} else {
			diffuse_stepped = original_stepped;
		}
	}

	diffuse_stepped = max(diffuse_stepped, min_ambient);
	vec3 diffuse = ALBEDO.rgb * LIGHT_COLOR / PI;
	diffuse *= diffuse_stepped;
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, diffuse);
}
