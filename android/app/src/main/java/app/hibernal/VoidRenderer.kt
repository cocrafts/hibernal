package app.hibernal

import android.os.Handler
import android.os.HandlerThread
import android.service.wallpaper.WallpaperService
import android.util.Log
import android.view.Choreographer
import android.view.Surface
import java.util.concurrent.CountDownLatch

object VoidRenderer : Choreographer.FrameCallback {
    // Under the 16.7 ms and 33.3 ms frame periods, so vsync jitter does not drop a frame that
    // arrives a little early: 60 fps in the app, 30 for the always-on wallpaper.
    private const val APP_MIN_FRAME_NANOS = 15_000_000L
    private const val WALLPAPER_MIN_FRAME_NANOS = 30_000_000L
    private const val TAG = "VoidRender"

    private class Target(val surface: Surface, val width: Int, val height: Int, val inApp: Boolean) {
        val minFrameNanos = if (inApp) APP_MIN_FRAME_NANOS else WALLPAPER_MIN_FRAME_NANOS
    }

    private val thread = HandlerThread(TAG).apply { start() }
    private val handler = Handler(thread.looper)
    private val targets = LinkedHashMap<Any, Target>()
    private var activeOwner: Any? = null
    private var activeTarget: Target? = null
    private var ticking = false
    private var lastFrameNanos = 0L
    private var framesSinceLog = 0
    private var lastLogNanos = 0L

    fun show(owner: Any, surface: Surface, width: Int, height: Int) {
        handler.post {
            targets.remove(owner)
            targets[owner] = Target(surface, width, height, owner !is WallpaperService.Engine)
            bindLatest()
        }
    }

    fun hide(owner: Any) {
        val done = CountDownLatch(1)
        handler.post {
            targets.remove(owner)
            bindLatest()
            done.countDown()
        }
        done.await()
    }

    // The app's surface exists only while it is in front; the wallpaper engine also reports itself
    // visible then (on every touch, measured on the Seeker), and must not take the core from it.
    private fun bindLatest() {
        val owner = targets.entries.lastOrNull { it.value.inApp }?.key ?: targets.keys.lastOrNull()
        val target = owner?.let { targets[it] }
        if (target == null) {
            if (activeTarget != null) {
                VoidNative.detach()
                Log.i(TAG, "detach")
            }
            TiltSensor.stop()
            activeOwner = null
            activeTarget = null
            return
        }
        TiltSensor.start()
        val current = activeTarget
        if (owner === activeOwner && current != null && current.surface == target.surface) {
            if (current.width != target.width || current.height != target.height) {
                VoidNative.resize(target.width, target.height)
            }
        } else {
            VoidNative.attach(target.surface, target.width, target.height, target.inApp)
            Log.i(TAG, "attach ${owner.javaClass.simpleName} ${target.width}x${target.height}")
        }
        activeOwner = owner
        activeTarget = target
        if (!ticking) {
            ticking = true
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    private fun openWallpaperPicker() {
        val activity = activeOwner as? MainActivity
            ?: error("the wallpaper picker was asked for while drawing ${activeOwner?.javaClass?.simpleName}")
        activity.runOnUiThread { activity.openWallpaperPicker() }
    }

    override fun doFrame(frameTimeNanos: Long) {
        val target = activeTarget
        if (target == null) {
            ticking = false
            return
        }
        if (frameTimeNanos - lastFrameNanos >= target.minFrameNanos) {
            lastFrameNanos = frameTimeNanos
            VoidNative.frame()
            framesSinceLog++
            if (VoidNative.takeWallpaperPickerRequest()) openWallpaperPicker()
            val deathNoticeMark = VoidNative.takeDeathNoticeMark()
            if (deathNoticeMark >= 0) DeathNoticeStore.mark(GameSync.livePet, deathNoticeMark)
            val walletRequest = VoidNative.takeWalletRequest()
            if (walletRequest != 0) {
                val activity = activeOwner as? MainActivity
                if (activity != null && target.inApp) {
                    activity.runOnUiThread { activity.handleWalletRequest(walletRequest) }
                } else {
                    // A wallpaper/background request is consumed, never deferred to app resume.
                    VoidNative.setWalletState(4, "")
                }
            }
            val ownerActionRequest = VoidNative.takeOwnerActionRequest()
            if (ownerActionRequest != 0) {
                val activity = activeOwner as? MainActivity
                if (activity != null && target.inApp) {
                    activity.runOnUiThread { activity.handleOwnerActionRequest(ownerActionRequest) }
                } else {
                    VoidNative.setOwnerActionState(OwnerSigning.Outcome.CANCELLED.ordinal)
                }
            }
        }
        if (frameTimeNanos - lastLogNanos >= 1_000_000_000L) {
            Log.i(TAG, "fps=$framesSinceLog")
            framesSinceLog = 0
            lastLogNanos = frameTimeNanos
        }
        Choreographer.getInstance().postFrameCallback(this)
    }
}
