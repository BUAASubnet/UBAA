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
import platform.CoreCrypto.CCCryptorCreateWithMode
import platform.CoreCrypto.CCCryptorFinal
import platform.CoreCrypto.CCCryptorRefVar
import platform.CoreCrypto.CCCryptorRelease
import platform.CoreCrypto.CCCryptorUpdate
import platform.CoreCrypto.ccNoPadding
import platform.CoreCrypto.kCCAlgorithmAES
import platform.CoreCrypto.kCCDecrypt
import platform.CoreCrypto.kCCEncrypt
import platform.CoreCrypto.kCCModeCFB
import platform.CoreCrypto.kCCSuccess

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
  ): ByteArray = memScoped {
    val cryptor: CPointer<CCCryptorRefVar> = alloc<CCCryptorRefVar>().ptr
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
                0u,
                cryptor,
            )
          }
        }
    if (createStatus != kCCSuccess) {
      error("AES/CFB create operation failed with status $createStatus")
    }

    try {
      val output = ByteArray(input.size + 16)
      val updateLength: CPointer<ULongVar> = alloc<ULongVar>().ptr
      val finalLength: CPointer<ULongVar> = alloc<ULongVar>().ptr
      val updateStatus =
          input.usePinned { inputPinned ->
            output.usePinned { outputPinned ->
              CCCryptorUpdate(
                  cryptor.pointed.value,
                  inputPinned.addressOf(0),
                  input.size.convert(),
                  outputPinned.addressOf(0),
                  output.size.convert(),
                  updateLength,
              )
            }
          }
      if (updateStatus != kCCSuccess) {
        error("AES/CFB update operation failed with status $updateStatus")
      }

      val finalStatus =
          output.usePinned { outputPinned ->
            CCCryptorFinal(
                cryptor.pointed.value,
                outputPinned.addressOf(updateLength.pointed.value.toInt()),
                (output.size - updateLength.pointed.value.toInt()).convert(),
                finalLength,
            )
          }
      if (finalStatus != kCCSuccess) {
        error("AES/CFB final operation failed with status $finalStatus")
      }

      output.copyOf((updateLength.pointed.value + finalLength.pointed.value).toInt())
    } finally {
      CCCryptorRelease(cryptor.pointed.value)
    }
  }
}
