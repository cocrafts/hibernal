// The HUD's last pass: hudPost.glsl's program, registered with the GPU door (void src/gpu/door.h).
#ifndef HUD_POST_H
#define HUD_POST_H

#include <stdint.h>

// Registers the composite program on `fullscreenLayout`, a door layout id; answers its door
// program id.
int32_t hudPostRegister(int32_t fullscreenLayout);

#endif
