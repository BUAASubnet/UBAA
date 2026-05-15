package cn.edu.ubaa.api.plantform

import kotlinx.cinterop.UByteVar
import kotlinx.cinterop.addressOf
import kotlinx.cinterop.alloc
import kotlinx.cinterop.convert
import kotlinx.cinterop.memScoped
import kotlinx.cinterop.ptr
import kotlinx.cinterop.reinterpret
import kotlinx.cinterop.usePinned
import platform.CoreFoundation.CFDataCreate
import platform.CoreFoundation.CFDataGetBytePtr
import platform.CoreFoundation.CFDataGetLength
import platform.CoreFoundation.CFDictionaryCreateMutable
import platform.CoreFoundation.CFDictionaryRef
import platform.CoreFoundation.CFDictionarySetValue
import platform.CoreFoundation.CFErrorRefVar
import platform.CoreFoundation.kCFAllocatorDefault
import platform.Security.SecKeyCreateEncryptedData
import platform.Security.SecKeyCreateWithData
import platform.Security.kSecAttrKeyClass
import platform.Security.kSecAttrKeyClassPublic
import platform.Security.kSecAttrKeyType
import platform.Security.kSecAttrKeyTypeRSA
import platform.Security.kSecKeyAlgorithmRSAEncryptionPKCS1
import platform.posix.memcpy

internal actual object PlatformRsaPkcs1Encrypt {
  actual fun encrypt(input: ByteArray, publicKeyDer: ByteArray): ByteArray = memScoped {
    val error = alloc<CFErrorRefVar>()
    val publicKey =
        SecKeyCreateWithData(publicKeyDer.toCfData(), keyAttributes(), error.ptr)
            ?: error("RSA public key initialization failed")
    val encrypted =
        SecKeyCreateEncryptedData(
            publicKey,
            kSecKeyAlgorithmRSAEncryptionPKCS1,
            input.toCfData(),
            error.ptr,
        ) ?: error("RSA encryption failed")
    encrypted.toByteArray()
  }

  private fun keyAttributes(): CFDictionaryRef {
    val attributes =
        CFDictionaryCreateMutable(kCFAllocatorDefault, 0, null, null)
            ?: error("RSA key attributes allocation failed")
    CFDictionarySetValue(attributes, kSecAttrKeyType, kSecAttrKeyTypeRSA)
    CFDictionarySetValue(attributes, kSecAttrKeyClass, kSecAttrKeyClassPublic)
    return attributes
  }

  private fun ByteArray.toCfData() = usePinned { pinned ->
    CFDataCreate(kCFAllocatorDefault, pinned.addressOf(0).reinterpret<UByteVar>(), size.convert())
        ?: error("CFData allocation failed")
  }

  private fun platform.CoreFoundation.CFDataRef.toByteArray(): ByteArray {
    val length = CFDataGetLength(this).toInt()
    val source = CFDataGetBytePtr(this) ?: return ByteArray(0)
    return ByteArray(length).also { result ->
      result.usePinned { pinned -> memcpy(pinned.addressOf(0), source, length.convert()) }
    }
  }
}
