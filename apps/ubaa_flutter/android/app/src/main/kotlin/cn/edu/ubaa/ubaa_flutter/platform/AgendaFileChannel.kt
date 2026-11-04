package cn.edu.ubaa.ubaa_flutter.platform

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** 系统选择器只取得目标，Dart 核对账号与路线后单独提交日历内容。 */
class AgendaFileChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cn.edu.buaa.ubaa/agenda-file")
    private var pending: MethodChannel.Result? = null
    private var target: Uri? = null
    private var selection = 0
    private var binarySelection = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "select" -> {
                    if (pending != null || target != null) {
                        result.error("busy", "请先结束当前保存操作", null)
                    } else {
                        binarySelection = call.argument<String>("kind") == "binary"
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = if (binarySelection) "application/octet-stream" else "text/calendar"
                            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
                        }
                        pending = result
                        try { activity.startActivityForResult(intent, REQUEST) }
                        catch (_: Exception) { pending = null; result.error("unavailable", "无法打开保存面板", null) }
                    }
                }
                "write", "writeFile", "discard" -> {
                    val uri = target
                    if (uri == null || call.argument<String>("selection") != selection.toString()) {
                        result.error("expired", "保存位置已失效", null)
                    } else {
                        target = null
                        val binary = binarySelection
                        if (call.method == "writeFile") {
                            val source = call.argument<String>("path")
                            if (source == null) { result.error("invalid", "缺少本机文件", null) }
                            else Thread {
                                try {
                                    File(source).inputStream().use { input ->
                                        requireNotNull(activity.contentResolver.openOutputStream(uri, "wt")).use { output -> input.copyTo(output, 64 * 1024) }
                                    }
                                    activity.runOnUiThread { result.success(null) }
                                } catch (_: Exception) {
                                    if (binary) discardBinary(uri)
                                    activity.runOnUiThread { result.error("write_failed", "文件未保存", null) }
                                }
                            }.start()
                        } else try {
                            if (call.method == "write") {
                                val bytes = requireNotNull(call.argument<ByteArray>("bytes"))
                                requireNotNull(activity.contentResolver.openOutputStream(uri, "wt")).use { it.write(bytes) }
                            } else if (binary) discardBinary(uri)
                            result.success(null)
                        } catch (_: Exception) { result.error("write_failed", "文件未保存", null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun discardBinary(uri: Uri) {
        try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) { }
    }

    fun onActivityResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending ?: return true
        pending = null
        target = if (resultCode == Activity.RESULT_OK) data?.data else null
        selection++
        result.success(if (target == null) null else selection.toString())
        return true
    }

    fun dispose() {
        pending?.error("closed", "保存面板已关闭", null)
        pending = null
        target = null
        channel.setMethodCallHandler(null)
    }

    companion object { private const val REQUEST = 27139 }
}
