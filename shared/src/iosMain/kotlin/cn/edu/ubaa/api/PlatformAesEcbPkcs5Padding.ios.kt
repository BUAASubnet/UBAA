package cn.edu.ubaa.api

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.size_tVar
import kotlinx.cinterop.usePinned
import platform.CommonCrypto.CCCrypt
import platform.CommonCrypto.kCCAlgorithmAES
import platform.CommonCrypto.kCCDecrypt
import platform.CommonCrypto.kCCEncrypt
import platform.CommonCrypto.kCCOptionECBMode
import platform.CommonCrypto.kCCOptionPKCS7Padding
import platform.CommonCrypto.kCCSuccess

internal actual object PlatformAesEcbPkcs5Padding {
  actual fun encrypt(input: ByteArray, key: ByteArray): ByteArray =
      runCipher(kCCEncrypt, input, key)

  actual fun decrypt(input: ByteArray, key: ByteArray): ByteArray =
      runCipher(kCCDecrypt, input, key)

  private fun runCipher(operation: UInt, input: ByteArray, key: ByteArray): ByteArray {
    val output = ByteArray(input.size + 16)
    return memScoped {
      val outputLength = alloc<size_tVar>()
      val status =
          input.usePinned { inputPinned ->
            key.usePinned { keyPinned ->
              output.usePinned { outputPinned ->
                CCCrypt(
                    operation,
                    kCCAlgorithmAES,
                    (kCCOptionPKCS7Padding or kCCOptionECBMode).convert(),
                    keyPinned.addressOf(0),
                    key.size.convert(),
                    null,
                    inputPinned.addressOf(0),
                    input.size.convert(),
                    outputPinned.addressOf(0),
                    output.size.convert(),
                    outputLength.ptr,
                )
              }
            }
          }
      if (status != kCCSuccess) {
        error("AES/ECB operation failed with status $status")
      }
      output.copyOf(outputLength.value.toInt())
    }
  }
}
