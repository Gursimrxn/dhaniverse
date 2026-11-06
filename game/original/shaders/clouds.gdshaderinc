// Cloud shadow system - world-space cloud simulation
// Adapted from Dylearn's cloud shader (MIT License)

global uniform sampler2D cloud_noise;
global uniform float cloud_scale = 0.002;
global uniform float cloud_world_y = 20.0;
global uniform float cloud_speed = -0.01;
global uniform float cloud_contrast = 3.845;
global uniform float cloud_threshold = 0.0;
global uniform vec2 cloud_direction = vec2(0.0, 1.0);
global uniform vec3 light_direction;
global uniform float cloud_shadow_min = 0.2;
global uniform float cloud_diverge_angle = 10.0;

vec2 rotate_vec2(vec2 vector, float angle) {
	float angle_rad = angle * (PI / 180.0);
	float rotated_x = (vector.x * cos(angle_rad)) - (vector.y * sin(angle_rad));
	float rotated_y = (vector.x * sin(angle_rad)) + (vector.y * cos(angle_rad));
	return vec2(rotated_x, rotated_y);
}

float get_cloud_shadow(vec3 world_pos) {
	if (cloud_scale <= 0.0 || cloud_contrast <= 0.0) {
		return 1.0;
	}
	float t = (cloud_world_y - world_pos.y) / max(light_direction.y, 0.001);
	vec3 hit_pos = world_pos + t * light_direction;
	float inv_scale = 1.0 / max(cloud_scale, 0.0001);

	vec2 cloud_dir1 = rotate_vec2(cloud_direction, cloud_diverge_angle);
	vec2 cloud_dir2 = rotate_vec2(cloud_direction, -cloud_diverge_angle);
	vec2 cloud_time1 = TIME * cloud_speed * normalize(cloud_dir1);
	vec2 cloud_time2 = TIME * cloud_speed * normalize(cloud_dir2);

	float sample1 = texture(cloud_noise, hit_pos.xz * inv_scale + cloud_time1).r;
	float sample2 = texture(cloud_noise, hit_pos.xz * (inv_scale * 0.8) + (cloud_time2 * 0.89 * PI / 3.0)).r;

	float cloud_sample = sample1 * sample2;
	float light_value = clamp(cloud_sample + cloud_threshold, 0.0, 1.0);
	light_value = (light_value - 0.5) * cloud_contrast + 0.5;
	light_value = clamp(light_value + cloud_threshold, cloud_shadow_min, 1.0);
	return light_value;
}
