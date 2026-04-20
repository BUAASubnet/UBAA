package cn.edu.ubaa.api

internal actual object PlatformMd5Hex {
  actual fun digest(input: ByteArray): String =
      error("MD5 is unsupported on Wasm local CGYY runtime")
}
