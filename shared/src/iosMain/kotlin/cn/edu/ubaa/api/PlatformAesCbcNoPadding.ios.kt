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
import platform.CoreCrypto.kCCSuccess

internal actual object PlatformAesCbcNoPadding {
  actual fun encrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      runCipher(kCCEncrypt, input, key, iv)

  actual fun decrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      runCipher(kCCDecrypt, input, key, iv)

  private fun runCipher(
      operation: UInt,
      input: ByteArray,
      key: ByteArray,
      iv: ByteArray,
  ): ByteArray {
    val output = ByteArray(input.size + 16)
    return memScoped {
      val outputLength: CPointer<ULongVar> = alloc<ULongVar>().ptr
      val status =
          input.usePinned { inputPinned ->
            key.usePinned { keyPinned ->
              iv.usePinned { ivPinned ->
                output.usePinned { outputPinned ->
                  CCCrypt(
                      operation,
                      kCCAlgorithmAES,
                      0u,
                      keyPinned.addressOf(0),
                      key.size.convert(),
                      ivPinned.addressOf(0),
                      inputPinned.addressOf(0),
                      input.size.convert(),
                      outputPinned.addressOf(0),
                      output.size.convert(),
                      outputLength,
                  )
                }
              }
            }
          }
      if (status != kCCSuccess) {
        error("AES/CBC operation failed with status $status")
      }
      output.copyOf(outputLength.pointed.value.toInt())
    }
  }
}
