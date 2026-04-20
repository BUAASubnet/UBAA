package cn.edu.ubaa.api

import java.io.ByteArrayInputStream
import javax.imageio.ImageIO

internal actual object PlatformImageRasterDecoder {
  actual fun decode(input: ByteArray): LocalCgyyImageData {
    val image =
        ImageIO.read(ByteArrayInputStream(input))
            ?: error("Failed to decode CGYY captcha image")
    val pixels = IntArray(image.width * image.height)
    image.getRGB(0, 0, image.width, image.height, pixels, 0, image.width)
    return LocalCgyyImageData(
        width = image.width,
        height = image.height,
        argb = pixels,
    )
  }
}
