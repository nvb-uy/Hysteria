#if !defined MATERIAL_INCLUDED
#define MATERIAL_INCLUDED

#include "aces/matrices.glsl"
#include "utility/color.glsl"

struct Material {
	vec3 albedo;
	vec3 f0;
	vec3 f82; // hardcoded metals only
	float roughness;
	float refractiveIndex;
	float sssAmount;
	float porosity;
	float emission;
	bool isMetal;
	bool isHardcodedMetal;
};

#if TEXTURE_FORMAT == TEXTURE_FORMAT_LAB
void decodeSpecularTexture() {
	// f0 and f82 values for hardcoded metals from Jessie LC (https://github.com/Jessie-LC)
	const vec3[] metalF0 = vec3[](
		vec3(0.78, 0.77, 0.74), // Iron
		vec3(1.00, 0.90, 0.61), // Gold
		vec3(1.00, 0.98, 1.00), // Aluminum
		vec3(0.77, 0.80, 0.79), // Chrome
		vec3(1.00, 0.89, 0.73), // Copper
		vec3(0.79, 0.87, 0.85), // Lead
		vec3(0.92, 0.90, 0.83), // Platinum
		vec3(1.00, 1.00, 0.91)  // Silver
	);
	const vec3[] metalF82 = vec3[](
		vec3(0.74, 0.76, 0.76),
		vec3(1.00, 0.93, 0.73),
		vec3(0.96, 0.97, 0.98),
		vec3(0.74, 0.79, 0.78),
		vec3(1.00, 0.90, 0.80),
		vec3(0.83, 0.80, 0.83),
		vec3(0.89, 0.87, 0.81),
		vec3(1.00, 1.00, 0.95)
	);
}
#endif

Material getMaterial(vec3 albedoSrgb, uint blockId, vec3 fractWorldPos, inout vec2 lmCoord) {
	// Create material with default values

	Material material;
	material.albedo           = srgbToLinear(albedoSrgb) * rec709_to_rec2020;
	material.f0               = vec3(0.0);
	material.f82              = vec3(0.0);
	material.roughness        = 1.0;
	material.refractiveIndex  = 1.0;
	material.sssAmount        = 0.0;
	material.porosity         = 0.0;
	material.emission         = 0.0;
	material.isMetal          = false;
	material.isHardcodedMetal = false;

	// Hardcoded materials for specific blocks
	// Using binary split search to minimise branches per fragment (TODO: measure impact)

	vec3 hsl = rgbToHsl(albedoSrgb);

	if (blockId < 16u) { // 0-16
		if (blockId < 8u) { // 0-8
			if (blockId < 4u) { // 0-4
				if (blockId < 2u) { // 0-2
					if (blockId == 1u) {

					}
				} else { // 2-4
					if (blockId == 2u) {
						#ifdef HARDCODED_EMISSION
						// Bright full emissives
						material.emission = 1.00 * (0.1 + 0.9 * sqr(hsl.z));
						lmCoord.x *= 0.8;
						#endif
					} else {
						#ifdef HARDCODED_EMISSION
						// Medium full emissives
						material.emission = 0.66 * (0.1 + 0.9 * sqr(hsl.z));
						lmCoord.x *= 0.8;
						#endif
					}
				}
			} else { // 4-8
				if (blockId < 6u) { // 4-6
					if (blockId == 4u) {
						#ifdef HARDCODED_EMISSION
						// Dim full emissives
						material.emission = 0.33 * (0.1 + 0.9 * cube(hsl.z));
						lmCoord.x *= 0.95;
						#endif
					} else {
						#ifdef HARDCODED_EMISSION
						// Partial emissives (brightest parts glow)
						material.emission = 0.8 * step(0.495, 0.2 * hsl.y + 0.5 * hsl.z);
						lmCoord.x *= 0.88;
						#endif
					}
				} else { // 6-8, Torches
					#ifdef HARDCODED_EMISSION
					if (blockId == 6u) {
						// Ground torches and other partial emissives
						material.emission = 0.3 * cube(linearStep(0.2, 0.4, fractWorldPos.y));
					} else {
						// Wall torches
						material.emission = 0.3 * cube(linearStep(0.35, 0.6, fractWorldPos.y));
					}
					material.emission  = max(material.emission, step(0.5, 0.2 * hsl.y + 0.55 * hsl.z));
					material.emission *= lmCoord.x;
					lmCoord.x *= 0.75;
					#endif
				}
			}
		} else { // 8-16
			if (blockId < 12u) { // 8-12
				if (blockId < 10u) { // 8-10
					if (blockId == 8u) {
						#ifdef HARDCODED_EMISSION
						// Lava
						material.emission = 2.00 * (0.2 + 0.8 * isolateHue(hsl, 30.0, 15.0));
						lmCoord.x *= 0.3;
						#endif
					} else {
						#ifdef HARDCODED_EMISSION
						// Redstone components
						vec3 ap1 = material.albedo * rec2020_to_ap1_unlit;
						float l = 0.5 * (minOf(ap1) + maxOf(ap1));
						float redness = ap1.r * rcp(ap1.g + ap1.b);
						material.emission = 0.33 * step(0.45, redness * l);
						#endif
					}
				} else { // 10-12
					if (blockId == 10u) {
						#ifdef HARDCODED_EMISSION
						// Jack o' Lantern + nether mushrooms
						material.emission = 0.80 * step(0.73, 0.1 * hsl.y + 0.7 * hsl.z);
						lmCoord *= 0.9;
						#endif
					} else {
						#ifdef HARDCODED_EMISSION
						// Beacon
						material.emission = step(0.2, hsl.z) * step(maxOf(abs(fractWorldPos - 0.5)), 0.4);
						lmCoord *= 0.9;
						#endif
					}
				}
			} else { // 12-16
				if (blockId < 14u) { // 12-14
					if (blockId == 12u) {
						#ifdef HARDCODED_EMISSION
						// End portal frame
						material.emission = 0.33 * isolateHue(hsl, 120.0, 50.0);
						#endif
					} else {
						#ifdef HARDCODED_EMISSION
						// Sculk
						material.emission = 0.2 * isolateHue(hsl, 200.0, 40.0) * smoothstep(0.5, 0.7, hsl.z);
						#endif
					}
				} else { // 14-16
					if (blockId == 14u) {
						#ifdef HARDCODED_EMISSION
						// Pink glow
						material.emission = 2.0 * isolateHue(hsl, 310.0, 50.0);
						#endif
					} else {

					}
				}
			}
		}
	} else { // 16-32
		if (blockId < 24u) { // 16-24
			if (blockId < 20u) { // 16-20
				if (blockId < 18u) { // 16-18
					if (blockId == 16u) {
						// Small plants
						material.sssAmount = 0.5;
					} else {
						// Tall plants (lower half)
						material.sssAmount = 0.5;
					}
				} else { // 18-20
					if (blockId == 18u) {
						// Tall plants (upper half)
						material.sssAmount = 0.5;
					} else {
						// Leaves
						material.sssAmount = 1.0;
					}
				}
			} else { // 20-24
				if (blockId < 24u) { // 20-22
					if (blockId == 20u) {
						// Weak SSS
						material.sssAmount = 0.2;
					} else {
						// Strong SSS
						material.sssAmount = 0.6;
					}
				} else { // 22-24
					if (blockId == 22u) {

					} else {

					}
				}
			}
		} else { // 24-32
			if (blockId < 28u) { // 24-28
				if (blockId < 26u) { // 24-26
					if (blockId == 24u) {

					} else {

					}
				} else { // 26-28
					if (blockId == 26u) {

					} else {

					}
				}
			} else { // 28-32
				if (blockId < 30) { // 28-30
					if (blockId == 28u) {

					} else {

					}
				} else { // 30-32
					if (blockId == 30u) {

					} else {

					}
				}
			}
		}
	}

	return material;
}

#endif // MATERIAL_INCLUDED