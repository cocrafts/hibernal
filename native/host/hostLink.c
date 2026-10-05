// Host link (see hostLink.h).

#include <stdatomic.h>

#include "hostLink.h"

static atomic_int s_inApp;
static atomic_int s_wallpaperPlaces;
static atomic_int s_pickerRequested;

void hostSetInApp(int inApp) { atomic_store(&s_inApp, inApp); }
int hostInApp(void) { return atomic_load(&s_inApp); }

void hostSetWallpaperPlaces(int home, int lock) {
	atomic_store(&s_wallpaperPlaces, (home ? 1 : 0) | (lock ? 2 : 0));
}

int hostWallpaperPlaces(void) { return atomic_load(&s_wallpaperPlaces); }

void hostRequestWallpaperPicker(void) { atomic_store(&s_pickerRequested, 1); }
int hostTakeWallpaperPickerRequest(void) { return atomic_exchange(&s_pickerRequested, 0); }
