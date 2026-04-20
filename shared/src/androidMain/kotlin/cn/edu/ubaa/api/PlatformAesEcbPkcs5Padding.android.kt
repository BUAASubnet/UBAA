package cn.edu.ubaa.api

import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec

internal actual object PlatformAesEcbPkcs5Padding {
  actual fun encrypt(input: ByteArray, key: ByteArray): ByteArray =
      runCipher(Cipher.ENCRYPT_MODE, input, key)

  actual fun decrypt(input: ByteArray, key: ByteArray): ByteArray =
      runCipher(Cipher.DECRYPT_MODE, input, key)

  private fun runCipher(mode: Int, input: ByteArray, key: ByteArray): ByteArray {
    val cipher = Cipher.getInstance("AES/ECB/PKCS5Padding")
    cipher.init(mode, SecretKeySpec(key, "AES"))
    return cipher.doFinal(input)
  }
}
