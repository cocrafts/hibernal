// Tilt input: the phone's rotation as the Android shell last reported it (Sensor
// TYPE_GAME_ROTATION_VECTOR, as a unit quaternion w, x, y, z), read once per frame by tilt.ms.
// Pushes come from the UI thread and reads from the render thread, so both are guarded.
#ifndef HUD_TILT_H
#define HUD_TILT_H

void tiltPush(float w, float x, float y, float z);

// Copies the latest rotation into the frame's copy; 1 once any rotation has arrived, else 0.
int tiltTake(void);
float tiltW(void);
float tiltX(void);
float tiltY(void);
float tiltZ(void);

#endif
