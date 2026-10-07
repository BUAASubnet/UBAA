package cn.edu.ubaa.ubaa_flutter.platform

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** path_provider 尚未提供 noBackupFilesDir，只补这一个平台策略。 */
class PrivatePaths(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cn.edu.buaa.ubaa/private-paths")
    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "configDirectory") result.notImplemented()
            else try {
                val directory = java.io.File(context.noBackupFilesDir, "UBAA")
                check(directory.isDirectory || directory.mkdirs())
                result.success(directory.absolutePath)
            } catch (_: Exception) { result.error("path_unavailable", "应用私有目录暂不可用", null) }
        }
    }
    fun dispose() { channel.setMethodCallHandler(null) }
}
