package cn.edu.ubaa.ubaa_flutter.platform

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** 系统 GetContent 只授权所选图片，URI 与原始错误不离开原生层。 */
class PhotoChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "cn.edu.buaa.ubaa/platform")
    private val executor = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "photo.capability" -> result.success(!disposed)
                // 只确认能请求系统选择；读取授权在用户选择后由系统授予。
                "permission.request" -> result.success(if (call.arguments == "photos") "granted" else "unavailable")
                "photo.pick" -> {
                    if (pending != null || disposed) {
                        result.error("photo_busy", "图片选择器暂不可用", null)
                    } else {
                        pending = result
                        try {
                            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                                type = "image/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            activity.startActivityForResult(Intent.createChooser(intent, "选择图片"), requestCode)
                        } catch (_: Exception) { fail() }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        if (pending == null || disposed) return true
        if (resultCode == Activity.RESULT_CANCELED) { finish(null); return true }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { fail(); return true }
        executor.execute {
            try {
                val resolver = activity.contentResolver
                val bytes = resolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size() + count > maxBytes) throw IllegalArgumentException()
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw IllegalArgumentException()
                val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                val mime = options.outMimeType
                if (bytes.isEmpty() || options.outWidth <= 0 || options.outHeight <= 0 ||
                    mime == null || !mime.startsWith("image/")) throw IllegalArgumentException()
                val proposed = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                } ?: "所选图片"
                val valid = proposed.isNotEmpty() && proposed != "." && proposed != ".." &&
                    proposed == proposed.trim() && proposed.codePointCount(0, proposed.length) <= 128 &&
                    proposed.none { it == '/' || it == '\\' || it == '"' || Character.isISOControl(it) }
                if (!valid) throw IllegalArgumentException()
                finish(mapOf("bytes" to bytes, "fileName" to proposed, "mimeType" to mime))
            } catch (_: Exception) { fail() }
        }
        return true
    }

    private fun finish(value: Any?) {
        activity.runOnUiThread {
            val reply = pending
            pending = null
            if (!disposed) reply?.success(value)
        }
    }

    private fun fail() {
        activity.runOnUiThread {
            val reply = pending
            pending = null
            if (!disposed) reply?.error("photo_read_failed", "无法读取图片，请选择不超过10MiB的图片", null)
        }
    }

    fun dispose() {
        pending?.error("photo_unavailable", "图片选择已结束", null)
        pending = null
        disposed = true
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private companion object {
        const val requestCode = 7301
        const val maxBytes = 10 * 1024 * 1024
    }
}
