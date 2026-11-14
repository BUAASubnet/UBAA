package cn.edu.ubaa.ubaa_flutter.platform

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** 默认网络身份只用于本机恢复判定，不读取 WiFi 名称或设备地址。 */
class DefaultNetworkChannel(context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val handler = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "cn.edu.ubaa/default_network")
    private val events = EventChannel(messenger, "cn.edu.ubaa/default_network/events")
    private var callback: ConnectivityManager.NetworkCallback? = null

    init {
        methods.setMethodCallHandler { call, result ->
            if (call.method == "current") result.success(identity()) else result.notImplemented()
        }
        events.setStreamHandler(this)
    }

    private fun identity(): String? = manager.activeNetwork?.networkHandle?.toString()

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        onCancel(null)
        val listener = object : ConnectivityManager.NetworkCallback() {
            private fun publish() {
                handler.post {
                    if (callback === this) sink.success(identity())
                }
            }
            override fun onAvailable(network: Network) = publish()
            override fun onLost(network: Network) = publish()
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
        }
        callback = listener
        manager.registerDefaultNetworkCallback(listener)
        sink.success(identity())
    }

    override fun onCancel(arguments: Any?) {
        callback?.let { manager.unregisterNetworkCallback(it) }
        callback = null
    }

    fun dispose() {
        onCancel(null)
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }
}
