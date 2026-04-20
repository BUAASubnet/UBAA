package cn.edu.ubaa.api

internal expect object PlatformRsaPkcs1Encrypt {
  fun encrypt(input: ByteArray, publicKeyDer: ByteArray): ByteArray
}
