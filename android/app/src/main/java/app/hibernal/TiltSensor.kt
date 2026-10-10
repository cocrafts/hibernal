package app.hibernal

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.util.Log

// The phone's rotation for the camera's parallax (native/input/tilt.ms), listened to only while
// a surface is drawn. GAME_ROTATION_VECTOR leaves the compass out, so it never swings when the
// magnetometer recalibrates.
object TiltSensor : SensorEventListener {
    private const val TAG = "VoidTilt"

    private var manager: SensorManager? = null
    private var sensor: Sensor? = null
    private var listening = false
    private val quaternion = FloatArray(4)

    fun prepare(context: Context) {
        if (manager != null) return
        val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        manager = sensors
        sensor = sensors.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        if (sensor == null) Log.w(TAG, "no game rotation vector sensor: the camera keeps still")
    }

    fun start() {
        val sensors = manager ?: error("TiltSensor.start before prepare")
        val rotation = sensor ?: return
        if (listening) return
        sensors.registerListener(this, rotation, SensorManager.SENSOR_DELAY_GAME)
        listening = true
    }

    fun stop() {
        if (!listening) return
        manager?.unregisterListener(this)
        listening = false
    }

    override fun onSensorChanged(event: SensorEvent) {
        SensorManager.getQuaternionFromVector(quaternion, event.values)
        VoidNative.rotation(quaternion[0], quaternion[1], quaternion[2], quaternion[3])
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
}
