package cn.edu.ubaa.ubaa_flutter.platform

import android.graphics.Bitmap
import java.io.ByteArrayOutputStream

/** 沿旧版TakePicturePreview，在内存压缩JPEG92；不创建相机目标文件。 */
internal object CameraPhoto {
    fun encode(bitmap: Bitmap): Map<String, Any> {
        require(!bitmap.isRecycled && bitmap.width > 0 && bitmap.height > 0)
        val output = BoundedBytes()
        require(bitmap.compress(Bitmap.CompressFormat.JPEG, 92, output))
        val bytes = output.toByteArray()
        require(bytes.isNotEmpty())
        return mapOf("bytes" to bytes,
            "fileName" to "camera_${System.currentTimeMillis()}.jpg",
            "mimeType" to "image/jpeg")
    }

    private class BoundedBytes : ByteArrayOutputStream() {
        @Synchronized
        override fun write(value: Int) {
            require(count < maxBytes)
            super.write(value)
        }

        @Synchronized
        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            require(length >= 0 && length <= maxBytes - count)
            super.write(bytes, offset, length)
        }
    }

    private const val maxBytes = 10 * 1024 * 1024
}
