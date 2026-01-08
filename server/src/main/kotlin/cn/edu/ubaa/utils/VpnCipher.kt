package cn.edu.ubaa.utils

import io.github.cdimascio.dotenv.dotenv
import java.net.URI
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("VpnCipher")

/**
 * 北航 WebVPN 协议转换工具。 负责将普通内网 URL 转换为 WebVPN 加密格式的外部可访问 URL，反之亦然。 支持多种协议（HTTP, HTTPS, WS, WSS）及端口的处理。
 */
object VpnCipher {
  private val dotenv = dotenv { ignoreIfMissing = true }

  /** 是否启用 VPN 转换模式。可通过环境变量 USE_VPN 显式控制。 */
  var isEnabled: Boolean = (dotenv["USE_VPN"] ?: System.getenv("USE_VPN"))?.toBoolean() ?: false

  /** 自动检测当前网络环境。 尝试直连内网地址，若失败则自动开启 VPN 转换模式。 */
  fun autoDetectEnvironment() {
    if (dotenv["USE_VPN"] != null || System.getenv("USE_VPN") != null) return

    try {
      val connection =
        URI.create("https://byxt.buaa.edu.cn").toURL().openConnection()
          as java.net.HttpURLConnection
      connection.requestMethod = "HEAD"
      connection.connectTimeout = 3000
      connection.connect()
      isEnabled = !(connection.responseCode == 200 || connection.responseCode == 302)
      connection.disconnect()
    } catch (_: Exception) {
      isEnabled = true
    }
  }

  private const val KEY_STR = "wrdvpnisthebest!"
  private val KEY = KEY_STR.toByteArray(Charsets.UTF_8)
  private val IV = KEY_STR.toByteArray(Charsets.UTF_8)

  /** 加密主机名。使用 AES/CFB/NoPadding。 */
  fun encrypt(text: String, key: ByteArray = KEY, iv: ByteArray = IV): String {
    val plain = text.toByteArray(Charsets.UTF_8)
    val cipher = Cipher.getInstance("AES/CFB/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
    val ct = cipher.doFinal(plain + ByteArray((16 - plain.size % 16) % 16) { '0'.code.toByte() })
    return iv.toHex() + ct.toHex().substring(0, plain.size * 2)
  }

  /** 解密主机名。 */
  fun decrypt(text: String, key: ByteArray = KEY): String {
    val iv = hexToBytes(text.substring(0, 32))
    val ct = hexToBytes(text.substring(32).let { it + "0".repeat((32 - it.length % 32) % 32) })
    val cipher = Cipher.getInstance("AES/CFB/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
    return cipher.doFinal(ct).copyOf(text.length / 2 - 16).toString(Charsets.UTF_8)
  }

  /** 将标准 URL 转换为 WebVPN 格式。 */
  fun toVpnUrl(url: String): String {
    if (!isEnabled) return url
    return try {
      val u = URI.create(url).toURL()
      if (u.host == "d.buaa.edu.cn") return url
      val p =
        when {
          u.port == -1 -> u.protocol
          u.protocol == "http" && u.port == 80 -> "http"
          u.protocol == "https" && u.port == 443 -> "https"
          else -> "${u.protocol}-${u.port}"
        }
      "https://d.buaa.edu.cn/$p/${encrypt(u.host)}${u.path}${u.query?.let { "?$it" } ?: ""}${u.ref?.let { "#$it" } ?: ""}"
    } catch (_: Exception) {
      url
    }
  }

  /** 将字节数组转换为十六进制字符串。 */
  private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }

  /** 将十六进制字符串转换为字节数组。 */
  private fun hexToBytes(hex: String): ByteArray =
    ByteArray(hex.length / 2) {
      ((hex[it * 2].digitToInt(16) shl 4) or hex[it * 2 + 1].digitToInt(16)).toByte()
    }
}
