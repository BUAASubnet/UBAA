package cn.edu.ubaa.api

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.ULongVar
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.pointed
import kotlinx.cinterop.ptr
import kotlinx.cinterop.usePinned
import kotlinx.cinterop.value
import platform.CoreCrypto.CCCrypt
import platform.CoreCrypto.kCCAlgorithmAES
import platform.CoreCrypto.kCCDecrypt
import platform.CoreCrypto.kCCEncrypt
import platform.CoreCrypto.kCCOptionECBMode
import platform.CoreCrypto.kCCOptionPKCS7Padding
import platform.CoreCrypto.kCCSuccess

internal actual object PlatformAesEcbPkcs5Padding {
  actual fun encrypt(input: ByteArray, key: ByteArray): ByteArray =
      runCipher(kCCEncrypt, input, key)

  actual fun decrypt(input: ByteArray, key: ByteArray): ByteArray =
      runCipher(kCCDecrypt, input, key)

  private fun runCipher(operation: UInt, input: ByteArray, key: ByteArray): ByteArray {
    val output = ByteArray(input.size + 16)
    return memScoped {
      val outputLength: CPointer<ULongVar> = alloc<ULongVar>().ptr
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
                    outputLength,
                )
              }
            }
          }
      if (status != kCCSuccess) {
        error("AES/ECB operation failed with status $status")
      }
      output.copyOf(outputLength.pointed.value.toInt())
    }
  }
}
