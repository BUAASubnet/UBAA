package cn.edu.ubaa.api

internal actual object PlatformAesCbcNoPadding {
  actual fun encrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      error("Local AES support is unavailable on Wasm")

  actual fun decrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      error("Local AES support is unavailable on Wasm")
}
