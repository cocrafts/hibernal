// Pointer queue (see hudPointer.h).

#include <stdatomic.h>

#include "hudPointer.h"

#define HUD_POINTER_CAP 128

typedef struct {
	int phase;
	int id;
	float x;
	float y;
} VoidPointerEvent;

static VoidPointerEvent s_pending[HUD_POINTER_CAP];
static int s_pendingCount;
static VoidPointerEvent s_frame[HUD_POINTER_CAP];
static int s_frameCount;
static atomic_flag s_lock = ATOMIC_FLAG_INIT;

static void lock(void) {
	while (atomic_flag_test_and_set_explicit(&s_lock, memory_order_acquire)) {}
}

static void unlock(void) { atomic_flag_clear_explicit(&s_lock, memory_order_release); }

void hudPointerPush(int phase, int id, float x, float y) {
	lock();
	// A move only says where the pointer is now, so consecutive moves of one pointer
	// collapse into the last. Down, up and cancel are never dropped by that; if the
	// queue is still full, the newest event is lost, never an older transition.
	VoidPointerEvent *last = s_pendingCount > 0 ? &s_pending[s_pendingCount - 1] : 0;
	if (phase == HUD_POINTER_MOVE && last && last->phase == HUD_POINTER_MOVE && last->id == id) {
		last->x = x;
		last->y = y;
	} else if (s_pendingCount < HUD_POINTER_CAP) {
		s_pending[s_pendingCount++] = (VoidPointerEvent){ phase, id, x, y };
	}
	unlock();
}

int hudPointerTake(void) {
	lock();
	for (int i = 0; i < s_pendingCount; i++) s_frame[i] = s_pending[i];
	s_frameCount = s_pendingCount;
	s_pendingCount = 0;
	unlock();
	return s_frameCount;
}

static const VoidPointerEvent *at(int i) {
	static const VoidPointerEvent none = { HUD_POINTER_CANCEL, -1, 0.0f, 0.0f };
	return (i >= 0 && i < s_frameCount) ? &s_frame[i] : &none;
}

int hudPointerPhase(int i) { return at(i)->phase; }
int hudPointerId(int i) { return at(i)->id; }
float hudPointerX(int i) { return at(i)->x; }
float hudPointerY(int i) { return at(i)->y; }
