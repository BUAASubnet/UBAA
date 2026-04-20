package cn.edu.ubaa.api

import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

internal actual object PlatformAesCbcNoPadding {
  actual fun encrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      runCipher(Cipher.ENCRYPT_MODE, input, key, iv)

  actual fun decrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      runCipher(Cipher.DECRYPT_MODE, input, key, iv)

  private fun runCipher(mode: Int, input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray {
    val cipher = Cipher.getInstance("AES/CBC/NoPadding")
    cipher.init(mode, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
    return cipher.doFinal(input)
  }
}
