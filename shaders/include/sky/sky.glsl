#if !defined INCLUDE_SKY_SKY
#define INCLUDE_SKY_SKY

#include "/include/utility/color.glsl"
#include "/include/utility/dithering.glsl"
#include "/include/utility/fast_math.glsl"
#include "/include/utility/random.glsl"

// Stars based on https://www.shadertoy.com/view/Md2SR3

vec3 unstable_star_field(vec2 coord, float star_threshold) {
	const float min_temp = 3500.0;
	const float max_temp = 9500.0;

	vec4 noise = hash4(coord);

	float star = linear_step(star_threshold, 1.0, noise.x);
	      star = pow4(star) * STARS_INTENSITY;

	float temp = mix(min_temp, max_temp, noise.y);
	vec3 color = blackbody(temp);

	const float twinkle_speed = 2.0;
	float twinkle_amount = noise.z;
	float twinkle_offset = tau * noise.w;
	star *= 1.0 - twinkle_amount * cos(frameTimeCounter * twinkle_speed + twinkle_offset);

	return star * color;
}

// Stabilizes the star field by sampling at the four neighboring integer coordinates and
// interpolating
vec3 stable_star_field(vec2 coord, float star_threshold) {
	coord = abs(coord) + 33.3 * step(0.0, coord);
	vec2 i, f = modf(coord, i);

	f.x = cubic_smooth(f.x);
	f.y = cubic_smooth(f.y);

	return unstable_star_field(i + vec2(0.0, 0.0), star_threshold) * (1.0 - f.x) * (1.0 - f.y)
	     + unstable_star_field(i + vec2(1.0, 0.0), star_threshold) * f.x * (1.0 - f.y)
	     + unstable_star_field(i + vec2(0.0, 1.0), star_threshold) * f.y * (1.0 - f.x)
	     + unstable_star_field(i + vec2(1.0, 1.0), star_threshold) * f.x * f.y;
}

vec3 draw_stars(vec3 ray_dir) {
#if defined WORLD_OVERWORLD && defined SHADOW
	// Trick to make stars rotate with sun and moon
	mat3 rot = (sunAngle < 0.5)
		? mat3(shadowModelViewInverse)
		: mat3(-shadowModelViewInverse[0].xyz, shadowModelViewInverse[1].xyz, -shadowModelViewInverse[2].xyz);

	ray_dir *= rot;
#endif

	// Adjust star threshold so that brightest stars appear first
#if defined WORLD_OVERWORLD
	float star_threshold = 1.0 - 0.008 * STARS_COVERAGE * smoothstep(-0.2, 0.05, -sun_dir.y);
#else
	float star_threshold = 1.0 - 0.008 * STARS_COVERAGE;
#endif

	// Project ray direction onto the plane
	vec2 coord  = ray_dir.xy * rcp(abs(ray_dir.z) + length(ray_dir.xy)) + 41.21 * sign(ray_dir.z);
	     coord *= 600.0;

	return stable_star_field(coord, star_threshold);
}

//----------------------------------------------------------------------------//
#if   defined WORLD_OVERWORLD

#include "/include/light/colors/light_color.glsl"
#include "/include/light/colors/weather_color.glsl"
#include "/include/light/bsdf.glsl"
#include "/include/sky/atmosphere.glsl"
#include "/include/sky/projection.glsl"
#include "/include/utility/geometry.glsl"

const float sun_luminance  = 40.0; // luminance of sun disk
const float moon_luminance = 20.0; // luminance of moon disk

vec3 draw_sun(vec3 ray_dir) {
	float nu = dot(ray_dir, sun_dir);

	// Limb darkening model from http://www.physics.hmc.edu/faculty/esin/a101/limbdarkening.pdf
	const vec3 alpha = vec3(0.429, 0.522, 0.614);
	float center_to_edge = max0(sun_angular_radius - fast_acos(nu));
	vec3 limb_darkening = pow(vec3(1.0 - sqr(1.0 - center_to_edge)), 0.5 * alpha);

	return sun_luminance * sun_color * step(0.0, center_to_edge) * limb_darkening;
}

vec4 get_clouds_and_aurora(vec3 ray_dir, vec3 clear_sky) {
#if   defined PROGRAM_DEFERRED0
	ivec2 texel   = ivec2(gl_FragCoord.xy);
	      texel.x = texel.x % (sky_map_res.x - 4);

	float dither = interleaved_gradient_noise(vec2(texel));

	// Render clouds
	#ifndef BLOCKY_CLOUDS
	const vec3 air_viewer_pos = vec3(0.0, planet_radius, 0.0);
	CloudsResult result = draw_clouds(air_viewer_pos, ray_dir, clear_sky, -1.0, dither);
	#else
	CloudsResult result = clouds_not_hit;
	#endif

	// Render aurora
	vec3 aurora = draw_aurora(ray_dir, dither);

	return vec4(
		result.scattering + aurora * result.transmittance,
		result.transmittance
	);
#else
	return vec4(0.0, 0.0, 0.0, 1.0);
#endif
}

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 draw_sky(vec3 ray_dir, vec3 atmosphere) {
	vec3 sky = vec3(0.0);

	// Sun, moon and stars

#if defined PROGRAM_DEFERRED4
	vec4 vanilla_sky = texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0);
	vec3 vanilla_sky_color = from_srgb(vanilla_sky.rgb);

	uint vanilla_sky_id = uint(255.0 * vanilla_sky.a);

#ifdef STARS
	sky += draw_stars(ray_dir);
#endif

#ifdef VANILLA_SUN
	if (vanilla_sky_id == 2) {
		const vec3 brightness_scale = sunlight_color * sun_luminance;
		sky += vanilla_sky_color * brightness_scale * sun_color;
	}
#else
	sky += draw_sun(ray_dir);
#endif

	if (vanilla_sky_id == 3) {
		const vec3 brightness_scale = sunlight_color * moon_luminance;
		sky *= 0.0; // Hide stars behind moon
		sky += vanilla_sky_color * brightness_scale;
	}

	#ifdef CUSTOM_SKY
	
	if (vanilla_sky_id == 4) {
		sky += vanilla_sky_color * CUSTOM_SKY_BRIGHTNESS;		
	}
	#endif
	#endif

	// Sky gradient

	sky *= atmosphere_transmittance(ray_dir.y, planet_radius) * (1.0 - rainStrength);
	sky += atmosphere;

	// Rain
	vec3 rain_sky = get_weather_color() * (1.0 - exp2(-0.8 / clamp01(ray_dir.y)));
	sky = mix(sky, rain_sky, rainStrength * mix(1.0, 0.9, time_sunrise + time_sunset));

	// Clouds

	vec4 clouds = get_clouds_and_aurora(ray_dir, sky);
	sky *= clouds.a;   // transmittance
	sky += clouds.rgb; // scattering

	// Fade lower part of sky into cave fog color when underground so that the sky isn't visible
	// beyond the render distance
	float underground_sky_fade = biome_cave * smoothstep(-0.1, 0.1, 0.4 - ray_dir.y);
	sky = mix(sky, vec3(0.0), underground_sky_fade);


	return sky;
}

vec3 draw_sky(vec3 ray_dir) {
	vec3 atmosphere = atmosphere_scattering(ray_dir, sun_color, sun_dir, moon_color, moon_dir);
	return draw_sky(ray_dir, atmosphere);
}

//----------------------------------------------------------------------------//
#elif defined WORLD_NETHER

vec3 draw_sky(vec3 ray_dir) {
	return ambient_color;
}

//----------------------------------------------------------------------------//
#elif defined WORLD_END

#include "/include/misc/end_lighting_fix.glsl"
#include "/include/sky/atmosphere.glsl"

const float sun_solid_angle = cone_angle_to_solid_angle(sun_angular_radius) * 1.5;
const vec3 end_sun_color = vec3(0.90, 0.20, 0.55);

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 getCosmicGlow(vec3 ray_dir, int iterations) {
    vec3 totalGlow = vec3(0.0);

    for (int i = 0; i < iterations; i++) {
        vec3 randomPosition = vec3(rand(vec2(i, i)), rand(vec2(i + 1, i + 1)), rand(vec2(i + 2, i + 2)));
        vec3 cosmicColor = vec3(rand(vec2(i + 3, i + 3)), rand(vec2(i + 4, i + 4)), rand(vec2(i + 5, i + 5))) * 0.333;

        float glowRadius = 1.5;
        float distanceToGlow = length(ray_dir - randomPosition);
        float glow = smoothstep(glowRadius, 0.0, distanceToGlow);
        totalGlow += cosmicColor * glow / 8 * END_COSMIC_GLOW_INTENSITY;
    }

    return totalGlow;
}

vec3 drawEndSkyFeatures(vec3 ray_dir) {
	float nu = dot(ray_dir, sun_dir);
	float r = fast_acos(nu);

	ray_dir.z *= -0.1; ray_dir.x *= -1.52;

	ray_dir *= mat3(
        cos(radians(-90.0)), -sin(radians(90.0)), 1.0,
        sin(radians(90.0)), cos(radians(-90.0)), 2.0,
        -0.0, 0.0, 0.0
    );

	ray_dir += 0.15;

	// Sun disk

	const vec3 alpha = vec3(0.6, 0.5, 0.4);
	float center_to_edge = max0(sun_angular_radius - r);
	vec3 limb_darkening = pow(vec3(1.0 - sqr(1.0 - center_to_edge)), -0.225 * alpha);
	vec3 sun_disk = vec3(r < sun_angular_radius);

	// Solar flare effect

	// Transform the coordinate space such that z is parallel to sun_dir
	vec3 tangent = sun_dir.y == 1.0 ? vec3(1.0, 0.0, 0.0) : normalize(cross(vec3(0.0, 1.0, 0.0), sun_dir));
	vec3 bitangent = normalize(cross(tangent, sun_dir));
	mat3 rot = mat3(tangent, bitangent, sun_dir) ;//* -18.37;

	// Vector from ray dir to sun dir
	vec2 q = ((ray_dir + sun_dir) * rot).xy;
	
	float theta = fract(linear_step(-pi, pi, atan(q.y, q.x)) + 0.015 * frameTimeCounter - 0.33 * r);

	float flare1 = texture(noisetex, vec2(theta, r - 0.025 * frameTimeCounter * 1.25)).x;
    flare1 = pow5(flare1) * exp(-25.0 * (r - sun_angular_radius));
    flare1 = r < sun_angular_radius ? 0.0 : flare1;

    float theta2 = fract(linear_step(-pi, pi, atan(q.y, q.x)) + -0.0002 * frameTimeCounter - 0.33 * (r + 0.05));
    float flare2 = texture(noisetex, vec2(theta2, r - 0.025 * frameTimeCounter)).x;
    flare2 = pow5(flare2) * exp(-20 * (r - sun_angular_radius / 2));
    flare2 = r < sun_angular_radius ? 0.0 : flare2;

    vec3 flare_color1 = end_sun_color;
    vec3 flare_color2 = vec3(0.8, 0.3, 0.0);

	// Black hole time!
    return
		#ifdef END_COSMIC_GLOW
		getCosmicGlow(ray_dir, 5) +
		#endif
		#ifdef END_BLACK_HOLE
		((vec3(0.0, 0.0, 0.0) * max0(sun_disk) ) * 100 
		+ flare_color1 * rcp(sun_solid_angle) * max0(0.5 * flare1) 
		+ flare_color2 * rcp(sun_solid_angle) * max0(1.5 * flare2));
		#else
		vec3(0.0);
		#endif
}

vec3 draw_sun(vec3 ray_dir) {
	return drawEndSkyFeatures(ray_dir);
}

vec3 draw_sky(vec3 ray_dir) {
	// Sky gradient

	float up_gradient = linear_step(0.0, 0.4, ray_dir.y) + linear_step(0.1, 0.8, -ray_dir.y);
	vec3 sky = ambient_color * mix(0.1, 0.04, up_gradient);
	float mie_phase = cornette_shanks_phase(dot(ray_dir, sun_dir), 0.6);
	sky += 0.1 * (ambient_color + 0.5 * end_sun_color) * mie_phase;

#if defined PROGRAM_DEFERRED4
	// Sun

	sky += draw_sun(ray_dir);

	// Stars

	vec3 stars_fade = exp2(-0.1 * max0(1.0 - ray_dir.y) / max(ambient_color, eps)) * linear_step(-0.2, 0.0, ray_dir.y);
	sky += draw_stars(ray_dir).xzy * stars_fade;
#endif

	return sky;
}

#endif

#endif // INCLUDE_SKY_SKY
