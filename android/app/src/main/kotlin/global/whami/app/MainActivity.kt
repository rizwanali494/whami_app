package global.whami.app

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.maplibre.android.net.ConnectivityReceiver

class MainActivity : FlutterActivity() {
    private val BAROMETER_CHANNEL = "global.whami.app/barometer"
    private var sensorManager: SensorManager? = null
    private var pressureSensor: Sensor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // WHAMI's vector map tiles are served from a local loopback HTTP
        // server (see MBTilesTileServer in Dart), not the real internet.
        // MapLibre Native's core HTTP file source gates ALL requests —
        // including ones to 127.0.0.1 — behind this OS-connectivity flag,
        // so without this override the entire map (vector tiles included)
        // goes blank whenever the device has no real internet connection,
        // even though the local tile server needs no network at all. This
        // is only reachable via the native SDK, not the maplibre_gl plugin's
        // Dart API (its setOffline() can only force offline or auto-detect,
        // never force "always connected").
        ConnectivityReceiver.instance(applicationContext).setConnected(true)

        // The override above can be clobbered later: MapLibre Native
        // (re-)activates its ConnectivityReceiver when the first map view
        // initializes, which re-queries the real OS connectivity state and
        // can overwrite our forced value. Expose a method Dart can call
        // again right when a map view is actually created (see
        // WhamiMapView._onMapCreated), so the override is reasserted after
        // that point too, not just once at engine-configure time.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "global.whami.app/maplibre_connectivity").setMethodCallHandler { call, result ->
            if (call.method == "forceConnected") {
                ConnectivityReceiver.instance(applicationContext).setConnected(true)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        pressureSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PRESSURE)

        // Method channel to check if the barometer is available
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "$BAROMETER_CHANNEL/method").setMethodCallHandler { call, result ->
            if (call.method == "isAvailable") {
                result.success(pressureSensor != null)
            } else {
                result.notImplemented()
            }
        }

        // Event channel to stream pressure readings
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$BAROMETER_CHANNEL/stream").setStreamHandler(
            object : EventChannel.StreamHandler {
                private var sensorEventListener: SensorEventListener? = null

                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    if (pressureSensor == null) {
                        events?.error("UNAVAILABLE", "Barometer not available", null)
                        return
                    }
                    sensorEventListener = object : SensorEventListener {
                        override fun onSensorChanged(event: SensorEvent?) {
                            if (event != null && event.sensor.type == Sensor.TYPE_PRESSURE) {
                                // pressure values[0] is in hPa (hectopascals) / mbar
                                events?.success(event.values[0].toDouble())
                            }
                        }
                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }
                    sensorManager?.registerListener(
                        sensorEventListener,
                        pressureSensor,
                        SensorManager.SENSOR_DELAY_NORMAL
                    )
                }

                override fun onCancel(arguments: Any?) {
                    sensorManager?.unregisterListener(sensorEventListener)
                    sensorEventListener = null
                }
            }
        )
    }
}
