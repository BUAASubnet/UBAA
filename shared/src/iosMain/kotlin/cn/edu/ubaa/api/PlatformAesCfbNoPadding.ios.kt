package cn.edu.ubaa.api

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.pin
import kotlinx.cinterop.ptr
import kotlinx.cinterop.size_tVar
import kotlinx.cinterop.usePinned
import platform.CommonCrypto.CCCryptorCreateWithMode
import platform.CommonCrypto.CCCryptorFinal
import platform.CommonCrypto.CCCryptorRefVar
import platform.CommonCrypto.CCCryptorRelease
import platform.CommonCrypto.CCCryptorUpdate
import platform.CommonCrypto.kCCAlgorithmAES
import platform.CommonCrypto.kCCDecrypt
import platform.CommonCrypto.kCCEncrypt
import platform.CommonCrypto.kCCModeCFB
import platform.CommonCrypto.kCCSuccess
import platform.CommonCrypto.ccNoPadding

internal actual object PlatformAesCfbNoPadding {
  actual fun encrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      runCipher(kCCEncrypt, input, key, iv)

  actual fun decrypt(input: ByteArray, key: ByteArray, iv: ByteArray): ByteArray =
      runCipher(kCCDecrypt, input, key, iv)

  private fun runCipher(
      operation: UInt,
      input: ByteArray,
      key: ByteArray,
      iv: ByteArray,
  ): ByteArray =
      memScoped {
        val cryptor = alloc<CCCryptorRefVar>()
        val createStatus =
            key.usePinned { keyPinned ->
              iv.usePinned { ivPinned ->
                CCCryptorCreateWithMode(
                    operation,
                    kCCModeCFB,
                    kCCAlgorithmAES,
                    ccNoPadding,
                    ivPinned.addressOf(0),
                    keyPinned.addressOf(0),
                    key.size.convert(),
                    null,
                    0.convert(),
                    0,
                    0,
                    cryptor.ptr,
                )
              }
            }
        if (createStatus != kCCSuccess) {
          error("AES/CFB create operation failed with status $createStatus")
        }

        try {
          val output = ByteArray(input.size + 16)
          val updateLength = alloc<size_tVar>()
          val finalLength = alloc<size_tVar>()
          val updateStatus =
              input.usePinned { inputPinned ->
                output.usePinned { outputPinned ->
                  CCCryptorUpdate(
                      cryptor.value,
                      inputPinned.addressOf(0),
                      input.size.convert(),
                      outputPinned.addressOf(0),
                      output.size.convert(),
                      updateLength.ptr,
                  )
                }
              }
          if (updateStatus != kCCSuccess) {
            error("AES/CFB update operation failed with status $updateStatus")
          }

          val finalStatus =
              output.usePinned { outputPinned ->
                CCCryptorFinal(
                    cryptor.value,
                    outputPinned.addressOf(updateLength.value.toInt()),
                    (output.size - updateLength.value.toInt()).convert(),
                    finalLength.ptr,
                )
              }
          if (finalStatus != kCCSuccess) {
            error("AES/CFB final operation failed with status $finalStatus")
          }

          output.copyOf((updateLength.value + finalLength.value).toInt())
        } finally {
          CCCryptorRelease(cryptor.value)
        }
      }
}
