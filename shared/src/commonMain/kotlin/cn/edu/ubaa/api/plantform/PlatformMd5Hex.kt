package cn.edu.ubaa.api.plantform

internal expect object PlatformMd5Hex {
  fun digest(input: ByteArray): String
}
