package ch.tellbow.alvyo

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.view.View
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.atan
import kotlin.math.min

// Recognising mountains (requirement 68), as PeakCamera.swift: the back
// camera's picture as a platform view ("alvyo/peak-camera"), the phone's
// attitude to true north with the camera's field of view as a stream
// ("alvyo/peak-motion"), and asking for the camera ("alvyo/camera").

/** The back camera's 4:3 picture, filling the view. */
class PeakCameraFactory(private val activity: FragmentActivity) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = PeakCameraView(activity)
}

class PeakCameraView(private val activity: FragmentActivity) : PlatformView {
    // A TextureView: Flutter draws it as a texture like the maps.
    private val preview = PreviewView(activity).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE }
    private var provider: ProcessCameraProvider? = null
    private val use =
        Preview.Builder()
            .setResolutionSelector(
                ResolutionSelector.Builder().setAspectRatioStrategy(AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY).build(),
            ).build()

    init {
        val future = ProcessCameraProvider.getInstance(activity)
        future.addListener({
            val p = future.get().also { provider = it }
            use.surfaceProvider = preview.surfaceProvider
            runCatching { p.bindToLifecycle(activity, CameraSelector.DEFAULT_BACK_CAMERA, use) }
        }, ContextCompat.getMainExecutor(activity))
    }

    override fun getView(): View = preview

    override fun dispose() {
        provider?.unbind(use)
    }
}

/** Asks for the camera; true when allowed. */
class CameraAccess(private val activity: FragmentActivity) {
    private var waiting: MethodChannel.Result? = null
    private val launcher: ActivityResultLauncher<String> =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            waiting?.success(granted)
            waiting = null
        }

    fun handle(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            return result.success(true)
        }
        waiting?.success(false)
        waiting = result
        launcher.launch(Manifest.permission.CAMERA)
    }
}

/**
 * The attitude 30 times a second, as PeakMotion in PeakCamera.swift but
 * as Android has it (turned in lib/peaks/projection.dart): the rotation
 * matrix from the device to east, magnetic north and up, row by row, and the
 * declination in degrees; the camera's field of view along the picture's
 * long side and that side over the short one; the compass's accuracy (-1
 * unreliable, 0 low … 2 high).
 */
class PeakMotion(context: Context) : EventChannel.StreamHandler, SensorEventListener {
    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val cameras = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private var events: EventChannel.EventSink? = null
    private var fov = 65.0
    private val r = FloatArray(9)

    // shortcut: the declination at Switzerland's centre (about 3°, ±1° across
    // the country), not where one stands; dragging the skyline makes up for it.
    private val declination = GeomagneticField(46.8f, 8.2f, 0f, System.currentTimeMillis()).declination.toDouble()

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        val sensor = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            ?: return sink.error("no-compass", "this device has no compass", null)
        fov = backCameraFov() ?: fov
        events = sink
        sensors.registerListener(this, sensor, 33_333)
    }

    override fun onCancel(arguments: Any?) {
        sensors.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val sink = events ?: return
        SensorManager.getRotationMatrixFromVector(r, event.values)
        sink.success(
            mapOf(
                "enu" to r.map { it.toDouble() },
                "declination" to declination,
                "fov" to fov,
                "aspect" to 4.0 / 3,
                "accuracy" to (event.accuracy - 1).coerceAtLeast(-1),
            ),
        )
    }

    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}

    /** Along the long side of the 4:3 picture the preview shows (the whole height of a wider sensor). */
    private fun backCameraFov(): Double? = runCatching {
        val id = cameras.cameraIdList.first {
            cameras.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        }
        val c = cameras.getCameraCharacteristics(id)
        val size = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)!!
        val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)!!.first()
        val long = min(maxOf(size.width, size.height), minOf(size.width, size.height) * 4f / 3)
        Math.toDegrees(2 * atan(long / (2.0 * focal)))
    }.getOrNull()
}
