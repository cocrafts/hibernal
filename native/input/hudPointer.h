// Pointer queue — touch and mouse, one shape for every host.
//
// The OS hit-tests nothing for us: everything is drawn into one surface, so all a host can
// report is "a pointer went down / moved / went up at (x, y) on your surface". Hosts push
// those raw events here (sokol_app's event callback on Linux, the Kotlin touch listener
// through JNI on Android); MetaScript takes the whole batch once per frame and does the
// hit-testing itself (pointer.ms, native/ui/ui.ms).
//
// Coordinates are surface pixels, origin top-left: what sokol_app and MotionEvent both give.
// Pushes may come from another thread than the frame (Android: UI thread vs render thread),
// so push and take are guarded; reads after a take touch only the frame's own copy.
#ifndef HUD_POINTER_H
#define HUD_POINTER_H

enum {
	HUD_POINTER_DOWN = 0,
	HUD_POINTER_MOVE = 1,
	HUD_POINTER_UP = 2,
	HUD_POINTER_CANCEL = 3,
};

void hudPointerPush(int phase, int id, float x, float y);

// Moves every pushed event into the frame's batch and returns how many there are. The
// batch stays readable through the getters below until the next take.
int hudPointerTake(void);
int hudPointerPhase(int i);
int hudPointerId(int i);
float hudPointerX(int i);
float hudPointerY(int i);

#endif
