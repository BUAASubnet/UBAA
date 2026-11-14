package cn.edu.ubaa.ubaa_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import cn.edu.ubaa.ubaa_flutter.platform.AppearanceChannel
import cn.edu.ubaa.ubaa_flutter.platform.AgendaFileChannel
import cn.edu.ubaa.ubaa_flutter.platform.DefaultNetworkChannel
import cn.edu.ubaa.ubaa_flutter.platform.PrivatePaths
import cn.edu.ubaa.ubaa_flutter.widgets.WidgetChannel

class MainActivity : FlutterActivity() {
    private external fun initializeTls(context: android.content.Context): Boolean
    private var network: DefaultNetworkChannel? = null
    private var paths: PrivatePaths? = null
    private var scheduleWidgets: WidgetChannel? = null
    private var appearance: AppearanceChannel? = null
    private var agendaFiles: AgendaFileChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        System.loadLibrary("ubaa_flutter_bridge")
        check(initializeTls(applicationContext)) { "系统证书验证初始化失败" }
        super.configureFlutterEngine(flutterEngine)
        network = DefaultNetworkChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        paths = PrivatePaths(this, flutterEngine.dartExecutor.binaryMessenger)
        scheduleWidgets = WidgetChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        appearance = AppearanceChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        agendaFiles = AgendaFileChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (agendaFiles?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        network?.dispose()
        network = null
        agendaFiles?.dispose()
        agendaFiles = null
        paths?.dispose()
        paths = null
        scheduleWidgets?.dispose()
        scheduleWidgets = null
        appearance?.dispose()
        appearance = null
        super.onDestroy()
    }
}
