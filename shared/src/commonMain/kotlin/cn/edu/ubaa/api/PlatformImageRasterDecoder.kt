package cn.edu.ubaa.api

internal data class LocalCgyyImageData(
    val width: Int,
    val height: Int,
    val argb: IntArray,
)

internal expect object PlatformImageRasterDecoder {
  fun decode(input: ByteArray): LocalCgyyImageData
}
