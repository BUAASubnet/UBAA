package cn.edu.ubaa.api

internal expect object PlatformAesCbcNoPadding {
  fun encrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray

  fun decrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray
}
