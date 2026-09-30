package pl.table.car

import android.content.Context
import androidx.car.app.connection.CarConnection
import androidx.lifecycle.LiveData
import androidx.lifecycle.Observer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Most między Table for employees a Android Auto:
 * „show” zapisuje bieżący kurs, a kanał „connection” mówi, czy telefon jest podłączony do samochodu.
 */
class TableCarPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var connection: LiveData<Int>? = null

    private val observer = Observer<Int> { type ->
        sink?.success(
            when (type) {
                CarConnection.CONNECTION_TYPE_PROJECTION, CarConnection.CONNECTION_TYPE_NATIVE -> "android_auto"
                else -> "none"
            },
        )
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "pl.table.car")
        channel.setMethodCallHandler(this)
        events = EventChannel(binding.binaryMessenger, "pl.table.car/connection")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        onCancel(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "ping" -> result.success(null)
            "show" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                CourseStore.update(context, JSONObject(args))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        val live = CarConnection(context).type
        connection = live
        live.observeForever(observer)
    }

    override fun onCancel(arguments: Any?) {
        connection?.removeObserver(observer)
        connection = null
        sink = null
    }
}
