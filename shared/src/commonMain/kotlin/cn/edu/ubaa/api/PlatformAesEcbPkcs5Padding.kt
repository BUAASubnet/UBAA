package cn.edu.ubaa.api

internal expect object PlatformAesEcbPkcs5Padding {
  fun encrypt(input: ByteArray, key: ByteArray): ByteArray

  fun decrypt(input: ByteArray, key: ByteArray): ByteArray
}
