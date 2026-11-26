package cn.edu.ubaa.ubaa_flutter.widgets

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

internal class WidgetChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    private val inbox: WidgetLaunchInbox,
) {
    private val channel = MethodChannel(messenger, "cn.edu.buaa.ubaa/schedule-widgets")
    private val launchChannel = MethodChannel(messenger, "cn.edu.buaa.ubaa/widget-launch")
    private val main = Handler(Looper.getMainLooper())

    init {
        inbox.awaitTake()
        launchChannel.setMethodCallHandler { call, result ->
            if (call.method == "take") result.success(inbox.take()) else result.notImplemented()
        }
        channel.setMethodCallHandler { call, result ->
            val arguments = call.arguments as? Map<*, *>
            if (call.method !in listOf("begin", "publish")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            ScheduleWidgetProvider.executor.execute {
                try {
                    val value: Any? =
                        if (call.method == "begin")
                            WidgetStore.begin(context, arguments?.get("owner") as? String)
                        else {
                            val scope = arguments?.get("scope") as? String ?: error("无发布代次")
                            val snapshot = arguments["snapshot"] as? Map<*, *> ?: error("无课表投影")
                            check(WidgetStore.publish(context, scope, JSONObject(snapshot))) {
                                "发布代次失效"
                            }
                            null
                        }
                    ScheduleWidgetProvider.refreshAll(context)
                    main.post { result.success(value) }
                } catch (_: Exception) {
                    // 安全存储已失效时也撤下Launcher的旧图，不能继续展示上一份课程。
                    runCatching { ScheduleWidgetProvider.refreshAll(context) }
                    main.post { result.error("widget_storage_failure", "桌面课表安全存储暂不可用", null) }
                }
            }
        }
    }

    fun launch(link: String) = launchChannel.invokeMethod("launch", link)

    fun dispose() {
        inbox.awaitTake()
        launchChannel.setMethodCallHandler(null)
        channel.setMethodCallHandler(null)
    }
}
