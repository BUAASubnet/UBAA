package cn.edu.ubaa.ubaa_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent
import cn.edu.ubaa.ubaa_flutter.platform.PhotoChannel
import cn.edu.ubaa.ubaa_flutter.widgets.WidgetChannel

class MainActivity : FlutterActivity() {
    private external fun initializeTls(context: android.content.Context): Boolean
    private var photos: PhotoChannel? = null
    private var scheduleWidgets: WidgetChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        System.loadLibrary("ubaa_flutter_bridge")
        check(initializeTls(applicationContext)) { "系统证书验证初始化失败" }
        super.configureFlutterEngine(flutterEngine)
        photos = PhotoChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        scheduleWidgets = WidgetChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (photos?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        photos?.dispose()
        photos = null
        scheduleWidgets?.dispose()
        scheduleWidgets = null
        super.onDestroy()
    }
}
