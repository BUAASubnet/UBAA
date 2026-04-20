package cn.edu.ubaa.api

import kotlinx.cinterop.addressOf
import kotlinx.cinterop.convert
import kotlinx.cinterop.usePinned
import platform.CommonCrypto.CC_MD5
import platform.CommonCrypto.CC_MD5_DIGEST_LENGTH

internal actual object PlatformMd5Hex {
  actual fun digest(input: ByteArray): String {
    val source = if (input.isEmpty()) byteArrayOf(0) else input
    val digest = ByteArray(CC_MD5_DIGEST_LENGTH.toInt())
    source.usePinned { sourcePinned ->
      digest.usePinned { digestPinned ->
        CC_MD5(sourcePinned.addressOf(0), input.size.convert(), digestPinned.addressOf(0))
      }
    }
    return digest.joinToString("") { byte -> byte.toUByte().toString(16).padStart(2, '0') }
  }
}
