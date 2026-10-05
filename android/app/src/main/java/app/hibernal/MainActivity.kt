package app.hibernal

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView

class MainActivity : Activity(), SurfaceHolder.Callback {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        VoidNative.prepare(applicationContext)
        val view = SurfaceView(this)
        view.holder.addCallback(this)
        // Every touch goes to Void, which draws and hit-tests the whole UI. A long press
        // used to open the wallpaper picker, but holding is now a gesture (dragging the pet),
        // so the picker moved to a three-finger tap.
        view.setOnTouchListener { _, e ->
            if (e.actionMasked == MotionEvent.ACTION_POINTER_DOWN && e.pointerCount == 3) {
                openWallpaperPicker()
            }
            VoidNative.forward(e)
            true
        }
        setContentView(view)
    }

    override fun onResume() {
        super.onResume()
        reportWallpaperPlaces()
    }

    override fun surfaceCreated(holder: SurfaceHolder) {}

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        VoidRenderer.show(this, holder.surface, width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        VoidRenderer.hide(this)
    }

    // The lock screen has no wallpaper of its own (id < 0) when it shows the home screen's.
    private fun reportWallpaperPlaces() {
        val manager = WallpaperManager.getInstance(this)
        val ours = ComponentName(this, VoidWallpaperService::class.java)
        val home = manager.wallpaperInfo?.component == ours
        val lock = if (manager.getWallpaperId(WallpaperManager.FLAG_LOCK) < 0) {
            home
        } else {
            Build.VERSION.SDK_INT >= 34 && manager.getWallpaperInfo(WallpaperManager.FLAG_LOCK)?.component == ours
        }
        VoidNative.setWallpaperPlaces(home, lock)
    }

    fun openWallpaperPicker() {
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
            .putExtra(
                WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                ComponentName(this, VoidWallpaperService::class.java),
            )
        startActivity(intent)
    }
}
