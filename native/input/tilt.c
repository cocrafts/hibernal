// Tilt input (see tilt.h).

#include <stdatomic.h>

#include "tilt.h"

static float s_pending[4] = { 1.0f, 0.0f, 0.0f, 0.0f };
static float s_frame[4] = { 1.0f, 0.0f, 0.0f, 0.0f };
static int s_arrived;
static atomic_flag s_lock = ATOMIC_FLAG_INIT;

static void lock(void) {
	while (atomic_flag_test_and_set_explicit(&s_lock, memory_order_acquire)) {}
}

static void unlock(void) { atomic_flag_clear_explicit(&s_lock, memory_order_release); }

void tiltPush(float w, float x, float y, float z) {
	lock();
	s_pending[0] = w;
	s_pending[1] = x;
	s_pending[2] = y;
	s_pending[3] = z;
	s_arrived = 1;
	unlock();
}

int tiltTake(void) {
	lock();
	for (int i = 0; i < 4; i++) s_frame[i] = s_pending[i];
	int arrived = s_arrived;
	unlock();
	return arrived;
}

float tiltW(void) { return s_frame[0]; }
float tiltX(void) { return s_frame[1]; }
float tiltY(void) { return s_frame[2]; }
float tiltZ(void) { return s_frame[3]; }
