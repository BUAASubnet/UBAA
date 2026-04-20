package cn.edu.ubaa.api

import android.graphics.BitmapFactory

internal actual object PlatformImageRasterDecoder {
  actual fun decode(input: ByteArray): LocalCgyyImageData {
    val bitmap =
        BitmapFactory.decodeByteArray(input, 0, input.size)
            ?: error("Failed to decode CGYY captcha image")
    val pixels = IntArray(bitmap.width * bitmap.height)
    bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
    return LocalCgyyImageData(
        width = bitmap.width,
        height = bitmap.height,
        argb = pixels,
    )
  }
}
