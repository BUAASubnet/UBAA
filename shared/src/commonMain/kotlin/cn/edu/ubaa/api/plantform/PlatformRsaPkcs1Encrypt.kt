package cn.edu.ubaa.api.plantform

internal expect object PlatformRsaPkcs1Encrypt {
  fun encrypt(input: ByteArray, publicKeyDer: ByteArray): ByteArray
}
