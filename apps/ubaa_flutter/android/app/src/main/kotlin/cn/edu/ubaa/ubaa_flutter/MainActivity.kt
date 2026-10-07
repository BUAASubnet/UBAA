package cn.edu.ubaa.ubaa_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import cn.edu.ubaa.ubaa_flutter.platform.PrivatePaths
import cn.edu.ubaa.ubaa_flutter.widgets.WidgetChannel

class MainActivity : FlutterActivity() {
    private external fun initializeTls(context: android.content.Context): Boolean
    private var paths: PrivatePaths? = null
    private var scheduleWidgets: WidgetChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        System.loadLibrary("ubaa_flutter_bridge")
        check(initializeTls(applicationContext)) { "系统证书验证初始化失败" }
        super.configureFlutterEngine(flutterEngine)
        paths = PrivatePaths(this, flutterEngine.dartExecutor.binaryMessenger)
        scheduleWidgets = WidgetChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        paths?.dispose()
        paths = null
        scheduleWidgets?.dispose()
        scheduleWidgets = null
        super.onDestroy()
    }
}
