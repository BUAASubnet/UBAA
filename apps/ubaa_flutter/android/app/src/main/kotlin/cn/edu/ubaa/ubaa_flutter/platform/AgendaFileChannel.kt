package cn.edu.ubaa.ubaa_flutter.platform

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
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
    private var pickingFolder = false
    private var pickingPrintFiles = false
    private var stagingPrintFiles = false
    private var closed = false
    private val printFiles = HashSet<String>()
    private var folder: Uri? = null
    private var writingFolder = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFiles" -> {
                    if (pending != null || target != null || folder != null || stagingPrintFiles) {
                        result.error("busy", "请先结束当前文件操作", null)
                    } else {
                        val types = call.argument<List<String>>("extensions").orEmpty().mapNotNull {
                            MimeTypeMap.getSingleton().getMimeTypeFromExtension(it)
                        }.distinct() + "application/octet-stream"
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                            putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
                        }
                        pending = result
                        pickingPrintFiles = true
                        try { activity.startActivityForResult(intent, REQUEST) }
                        catch (_: Exception) {
                            pending = null
                            pickingPrintFiles = false
                            result.error("unavailable", "无法打开文件选择面板", null)
                        }
                    }
                }
                "releaseFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null && printFiles.remove(path)) File(path).delete()
                    result.success(null)
                }
                "renderScanPdf" -> {
                    val path = call.argument<String>("path")
                    val page = call.argument<Int>("page")
                    if (path == null || page == null || page < 1) {
                        result.error("invalid", "缺少 PDF 或页码无效", null)
                    } else Thread {
                        try {
                            val payload = renderPdfPage(path, page)
                            activity.runOnUiThread { result.success(payload) }
                        } catch (_: Exception) {
                            activity.runOnUiThread { result.error("pdf_preview_failed", "无法打开 PDF", null) }
                        }
                    }.start()
                }
                "selectFolder" -> {
                    if (pending != null || target != null || folder != null) {
                        result.error("busy", "请先结束当前保存操作", null)
                    } else {
                        pickingFolder = true
                        pending = result
                        try {
                            activity.startActivityForResult(
                                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                                }, REQUEST
                            )
                        } catch (_: Exception) {
                            pending = null
                            pickingFolder = false
                            result.error("unavailable", "无法打开文件夹选择面板", null)
                        }
                    }
                }
                "writeFolderFile" -> {
                    val directory = folder
                    val name = call.argument<String>("name")
                    val path = call.argument<String>("path")
                    if (directory == null || writingFolder || call.argument<String>("selection") != selection.toString()
                        || name == null || name.isEmpty() || name == "." || name == ".." || name.contains('/') || path == null) {
                        result.error("invalid", "文件夹或文件名无效", null)
                    } else {
                        writingFolder = true
                        Thread {
                            try {
                                val actual = writeFolderFile(directory, name, path)
                                activity.runOnUiThread { writingFolder = false; result.success(actual) }
                            } catch (_: Exception) {
                                activity.runOnUiThread { writingFolder = false; result.error("write_failed", "文件未保存", null) }
                            }
                        }.start()
                    }
                }
                "discardFolder" -> {
                    if (folder != null && !writingFolder && call.argument<String>("selection") == selection.toString()) {
                        folder = null
                        result.success(null)
                    } else result.error("expired", "保存位置已失效", null)
                }
                "select" -> {
                    if (pending != null || target != null || folder != null) {
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

    private fun stagePrintFiles(data: Intent?, result: MethodChannel.Result) {
        val items = linkedSetOf<Uri>()
        data?.clipData?.let { clip ->
            for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { items.add(it) }
        }
        data?.data?.let { items.add(it) }
        if (items.size > 20) {
            result.error("too_many", "每批最多上传 20 份", null)
            return
        }
        if (items.isEmpty()) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        stagingPrintFiles = true
        Thread {
            val files = items.map { uri ->
                val resolver = activity.contentResolver
                val name = try {
                    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                        if (it.moveToFirst()) it.getString(0) else null
                    }
                } catch (_: Exception) { null }
                var local: File? = null
                val path = try {
                    val staged = File.createTempFile("print-", ".upload", activity.cacheDir)
                    local = staged
                    val limit = 32L * 1024 * 1024 + 1
                    var written = 0L
                    requireNotNull(resolver.openInputStream(uri)).use { input ->
                        staged.outputStream().use { output ->
                            val chunk = ByteArray(64 * 1024)
                            while (written < limit) {
                                val count = input.read(chunk, 0, minOf(chunk.size.toLong(), limit - written).toInt())
                                if (count <= 0) break
                                output.write(chunk, 0, count)
                                written += count
                            }
                        }
                    }
                    staged.path
                } catch (_: Exception) {
                    local?.delete()
                    ""
                }
                mapOf("path" to path, "name" to (name ?: "无法识别的文件"))
            }
            activity.runOnUiThread {
                stagingPrintFiles = false
                val paths = files.mapNotNull { it["path"]?.takeIf(String::isNotEmpty) }
                if (closed) {
                    paths.forEach { File(it).delete() }
                    result.error("closed", "文件选择已结束", null)
                } else {
                    printFiles.addAll(paths)
                    result.success(files)
                }
            }
        }.start()
    }

    private fun renderPdfPage(path: String, page: Int): Map<String, Any> {
        val descriptor = ParcelFileDescriptor.open(File(path), ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = try { PdfRenderer(descriptor) } catch (error: Exception) {
            descriptor.close()
            throw error
        }
        renderer.use { pdf ->
            pdf.openPage(page - 1).use { source ->
                val scale = 1800.0 / maxOf(source.width, source.height).coerceAtLeast(1)
                val bitmap = Bitmap.createBitmap(
                    (source.width * scale).roundToInt().coerceAtLeast(1),
                    (source.height * scale).roundToInt().coerceAtLeast(1),
                    Bitmap.Config.ARGB_8888
                )
                try {
                    bitmap.eraseColor(Color.WHITE)
                    source.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val png = ByteArrayOutputStream()
                    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, png))
                    return mapOf("totalPages" to pdf.pageCount, "image" to png.toByteArray())
                } finally { bitmap.recycle() }
            }
        }
    }

    private fun writeFolderFile(tree: Uri, name: String, path: String): String {
        val resolver = activity.contentResolver
        val id = DocumentsContract.getTreeDocumentId(tree)
        val directory = DocumentsContract.buildDocumentUriUsingTree(tree, id)
        val names = HashSet<String>()
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
        val nameColumn = DocumentsContract.Document.COLUMN_DISPLAY_NAME
        resolver.query(children, arrayOf(nameColumn), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) names.add(cursor.getString(0))
        }
        var candidate = name
        var suffix = 1
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        while (candidate in names) candidate = "$base (${suffix++})$extension"
        val mime = MimeTypeMap.getSingleton()
            .getMimeTypeFromExtension(extension.drop(1).lowercase()) ?: "application/octet-stream"
        val uri = requireNotNull(DocumentsContract.createDocument(resolver, directory, mime, candidate))
        try {
            File(path).inputStream().use { input ->
                requireNotNull(resolver.openOutputStream(uri, "wt")).use { output -> input.copyTo(output, 64 * 1024) }
            }
        } catch (error: Exception) {
            discardBinary(uri)
            throw error
        }
        return try {
            resolver.query(uri, arrayOf(nameColumn), null, null, null)?.use {
                if (it.moveToFirst()) it.getString(0) else null
            } ?: candidate
        } catch (_: Exception) { candidate }
    }

    private fun discardBinary(uri: Uri) {
        try { DocumentsContract.deleteDocument(activity.contentResolver, uri) } catch (_: Exception) { }
    }

    fun onActivityResult(request: Int, resultCode: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending ?: return true
        pending = null
        if (pickingPrintFiles) {
            pickingPrintFiles = false
            stagePrintFiles(if (resultCode == Activity.RESULT_OK) data else null, result)
            return true
        }
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (pickingFolder) folder = uri else target = uri
        pickingFolder = false
        selection++
        result.success(if (uri == null) null else selection.toString())
        return true
    }

    fun dispose() {
        closed = true
        printFiles.forEach { File(it).delete() }
        printFiles.clear()
        pending?.error("closed", "保存面板已关闭", null)
        pending = null
        target = null
        folder = null
        channel.setMethodCallHandler(null)
    }

    companion object { private const val REQUEST = 27139 }
}
