package cn.edu.ubaa.api

internal expect object PlatformMd5Hex {
  fun digest(input: ByteArray): String
}
