package cn.edu.ubaa.api

import java.security.MessageDigest

internal actual object PlatformMd5Hex {
  actual fun digest(input: ByteArray): String =
      MessageDigest.getInstance("MD5").digest(input).joinToString("") { "%02x".format(it) }
}
