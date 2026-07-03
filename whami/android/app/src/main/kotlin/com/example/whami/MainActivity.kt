package com.example.whami

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val BAROMETER_CHANNEL = "com.example.whami/barometer"
    private var sensorManager: SensorManager? = null
    private var pressureSensor: Sensor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
