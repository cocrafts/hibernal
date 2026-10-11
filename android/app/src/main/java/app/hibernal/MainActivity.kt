package app.hibernal

import android.Manifest
import android.app.NotificationManager
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.TextView
import androidx.activity.ComponentActivity

class MainActivity : ComponentActivity(), SurfaceHolder.Callback {
    private lateinit var walletBridge: WalletBridge

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        VoidNative.prepare(applicationContext)
        walletBridge = WalletBridge(this)
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
        val offline = TextView(this).apply {
            setTextColor(0xFFFF5040.toInt())
            setBackgroundColor(0xB0000000.toInt())
            setPadding(16, 8, 16, 8)
            visibility = android.view.View.GONE
        }
        setContentView(FrameLayout(this).apply {
            addView(view)
            addView(offline, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.CENTER_HORIZONTAL).apply { topMargin = 96 })
        })
        OfflineGame.attach(applicationContext) { scene ->
            runOnUiThread {
                offline.text = "OFFLINE · ${scene?.lowercase()}"
                offline.visibility = if (scene == null) android.view.View.GONE else android.view.View.VISIBLE
            }
        }
    }

    // Android asks at most twice; after that, and when notifications are off in Settings, only Settings can allow them.
    fun allowPetNews() {
        val preferences = getPreferences(MODE_PRIVATE)
        val granted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        val askable = !granted && (!preferences.getBoolean(PET_NEWS_ASKED, false) ||
            shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))
        if (askable) {
            preferences.edit().putBoolean(PET_NEWS_ASKED, true).apply()
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PET_NEWS_REQUEST)
            return
        }
        startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PET_NEWS_REQUEST) reportPetNews()
    }

    private fun reportPetNews() {
        VoidNative.setPetNewsAllowed(getSystemService(NotificationManager::class.java).areNotificationsEnabled())
    }

    override fun onResume() {
        super.onResume()
        reportWallpaperPlaces()
        reportPetNews()
        if (OfflineGame.active) OfflineGame.engage() else walletBridge.engage()
    }

    fun handleWalletRequest(request: Int) {
        if (OfflineGame.active) OfflineGame.walletRequest(request) else walletBridge.request(request)
    }

    fun handleOwnerActionRequest(request: Int) {
        if (OfflineGame.active) OfflineGame.ownerAction(request) else walletBridge.requestOwnerAction(request)
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

    private companion object {
        const val PET_NEWS_ASKED = "petNewsAsked"
        const val PET_NEWS_REQUEST = 1
    }
}
