// The HUD's last pass (see hudPost.h).

#include "hudPost.h"
#include "../../vendor/void/src/gpu/door.h"
#include "../../vendor/void/src/void3d/shader3d.glsl.h"
#include "hudPost.glsl.h"

_Static_assert(ATTR_hudPost_composite_position == ATTR_copy_position,
	"the composite reads the Fullscreen layout's position (void src/void3d/gpu3d.c)");
_Static_assert(sizeof(hudPost_hudPostParams_t) == 12 * 4, "hudPostParams must match HUD_POST_PARAMS in hudPost.ms");

int32_t hudPostRegister(int32_t fullscreenLayout) {
	static const door_shader_fn shaders[1] = { hudPost_composite_shader_desc };
	return doorRegisterPrograms(shaders, &fullscreenLayout, 1);
}
