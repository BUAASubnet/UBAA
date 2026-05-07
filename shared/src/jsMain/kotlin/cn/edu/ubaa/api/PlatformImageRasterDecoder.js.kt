package cn.edu.ubaa.api.plantform

internal actual object PlatformImageRasterDecoder {
  actual fun decode(input: ByteArray): LocalCgyyImageData =
      error("Image decode is unsupported on JS local CGYY runtime")
}
