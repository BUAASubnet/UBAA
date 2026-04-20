package cn.edu.ubaa.api

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.convert
import kotlinx.cinterop.usePinned
import platform.CoreGraphics.CGBitmapContextCreate
import platform.CoreGraphics.CGColorSpaceCreateDeviceRGB
import platform.CoreGraphics.CGContextDrawImage
import platform.CoreGraphics.CGImageGetHeight
import platform.CoreGraphics.CGImageGetWidth
import platform.CoreGraphics.CGRectMake
import platform.CoreGraphics.kCGImageAlphaPremultipliedLast
import platform.CoreGraphics.kCGBitmapByteOrder32Big
import platform.Foundation.NSData
import platform.Foundation.create
import platform.UIKit.UIImage

internal actual object PlatformImageRasterDecoder {
  actual fun decode(input: ByteArray): LocalCgyyImageData {
    val data =
        input.usePinned { pinned ->
          NSData.create(bytes = pinned.addressOf(0), length = input.size.toULong())
        }
    val image = UIImage(data = data) ?: error("Failed to decode CGYY captcha image")
    val cgImage = image.CGImage ?: error("Failed to access CGImage for captcha")
    val width = CGImageGetWidth(cgImage).toInt()
    val height = CGImageGetHeight(cgImage).toInt()
    val bytes = ByteArray(width * height * 4)
    val colorSpace = CGColorSpaceCreateDeviceRGB()
    bytes.usePinned { pinned ->
      val context =
          CGBitmapContextCreate(
              data = pinned.addressOf(0),
              width = width.convert(),
              height = height.convert(),
              bitsPerComponent = 8.convert(),
              bytesPerRow = (width * 4).convert(),
              space = colorSpace,
              bitmapInfo = (kCGImageAlphaPremultipliedLast or kCGBitmapByteOrder32Big),
          ) ?: error("Failed to create bitmap context for captcha")
      CGContextDrawImage(context, CGRectMake(0.0, 0.0, width.toDouble(), height.toDouble()), cgImage)
    }
    val pixels =
        IntArray(width * height) { index ->
          val offset = index * 4
          val r = bytes[offset].toInt() and 0xff
          val g = bytes[offset + 1].toInt() and 0xff
          val b = bytes[offset + 2].toInt() and 0xff
          val a = bytes[offset + 3].toInt() and 0xff
          (a shl 24) or (r shl 16) or (g shl 8) or b
        }
    return LocalCgyyImageData(width = width, height = height, argb = pixels)
  }
}
