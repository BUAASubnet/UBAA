package cn.edu.ubaa.ubaa_flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.content.Intent
import cn.edu.ubaa.ubaa_flutter.platform.PhotoChannel

class MainActivity : FlutterActivity() {
    private var photos: PhotoChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        photos = PhotoChannel(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (photos?.onActivityResult(requestCode, resultCode, data) != true) {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        photos?.dispose()
        photos = null
        super.onDestroy()
    }
}
