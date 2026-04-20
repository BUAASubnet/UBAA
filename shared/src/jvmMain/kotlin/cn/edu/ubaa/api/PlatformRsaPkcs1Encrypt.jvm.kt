package cn.edu.ubaa.api

import java.security.KeyFactory
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher

internal actual object PlatformRsaPkcs1Encrypt {
  actual fun encrypt(input: ByteArray, publicKeyDer: ByteArray): ByteArray {
    val publicKey = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(publicKeyDer))
    val cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding")
    cipher.init(Cipher.ENCRYPT_MODE, publicKey)
    return cipher.doFinal(input)
  }
}
