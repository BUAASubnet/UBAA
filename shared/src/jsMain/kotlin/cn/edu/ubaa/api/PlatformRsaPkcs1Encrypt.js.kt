package cn.edu.ubaa.api

internal actual object PlatformRsaPkcs1Encrypt {
  actual fun encrypt(input: ByteArray, publicKeyDer: ByteArray): ByteArray =
      error("Local BYKC RSA support is unavailable on JS")
}
