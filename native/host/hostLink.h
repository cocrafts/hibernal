// Host link: what the Android shell tells the core about the surface it draws on and the
// system wallpaper, and the one thing the core asks of the shell (open the wallpaper picker).
//
// The shell sets the surface kind on the render thread before a frame, sets the wallpaper
// places from the UI thread, and takes the picker request on the render thread after a frame.
#ifndef HOST_LINK_H
#define HOST_LINK_H

void hostSetInApp(int inApp);
int hostInApp(void);

void hostSetWallpaperPlaces(int home, int lock);
// Bit 0: on the home screen, bit 1: on the lock screen.
int hostWallpaperPlaces(void);

void hostRequestWallpaperPicker(void);
// 1 once per request, then 0 until the next one.
int hostTakeWallpaperPickerRequest(void);

#endif
