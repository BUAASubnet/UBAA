package cn.edu.ubaa.api

internal actual object PlatformAesEcbPkcs5Padding {
  actual fun encrypt(input: ByteArray, key: ByteArray): ByteArray =
      error("Local BYKC AES support is unavailable on JS")

  actual fun decrypt(input: ByteArray, key: ByteArray): ByteArray =
      error("Local BYKC AES support is unavailable on JS")
}
