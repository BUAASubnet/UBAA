package cn.edu.ubaa.utils;

import java.net.URL
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("VpnCipher")

/**
 * VPN URL 转换工具
 * 用于将普通URL转换为北航WebVPN格式的URL，反之亦然
 * 基于原项目的VpnCipher实现
 */
object VpnCipher {
private const val TAG = "VpnCipher"
private const val KEY_STR = "wrdvpnisthebest!"
private const val IV_STR = "wrdvpnisthebest!"
private val KEY = KEY_STR.toByteArray(Charsets.UTF_8)
private val IV = IV_STR.toByteArray(Charsets.UTF_8)

private fun ByteArray.toHex(): String =
joinToString("") { "%02x".format(it) }

private fun hexToBytes(hex: String): ByteArray {
    val len = hex.length
    val result = ByteArray(len / 2)
    for (i in 0 until len step 2) {
        result[i / 2] = ((hex[i].digitToInt(16) shl 4)
        or hex[i + 1].digitToInt(16)).toByte()
    }
    return result
}

private fun textRightAppend(data: ByteArray, mode: String): ByteArray {
    val segment = if (mode == "utf8") 16 else 32
    val padLen = (segment - data.size % segment) % segment
    return data + ByteArray(padLen) { '0'.code.toByte() }
}

/**
 * 加密文本
 * @param text 要加密的文本
 * @param key 加密密钥
 * @param iv 初始化向量
 * @return 加密后的十六进制字符串
 */
fun encrypt(text: String, key: ByteArray = KEY, iv: ByteArray = IV): String {
    val plain = text.toByteArray(Charsets.UTF_8)
    val origLen = plain.size
    val padded = textRightAppend(plain, "utf8")
    val cipher = Cipher.getInstance("AES/CFB/NoPadding")
    cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
    val ct = cipher.doFinal(padded)
    val ctHex = ct.toHex().substring(0, origLen * 2)
    return iv.toHex() + ctHex
}

/**
 * 解密文本
 * @param text 要解密的十六进制字符串
 * @param key 解密密钥
 * @return 解密后的文本
 */
fun decrypt(text: String, key: ByteArray = KEY): String {
    val ivHex = text.substring(0, 32)
    val ctHex = text.substring(32)
    val ivBytes = hexToBytes(ivHex)
    val ctPaddedHex = textRightAppend(ctHex.toByteArray(), "hex").toString(Charsets.UTF_8)
    val ct = hexToBytes(ctPaddedHex)
    val cipher = Cipher.getInstance("AES/CFB/NoPadding")
    cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(ivBytes))
    val pt = cipher.doFinal(ct)
    val origLen = ctHex.length / 2
    return pt.copyOf(origLen).toString(Charsets.UTF_8)
}

/**
 * 检查URL是否为VPN格式
 * @param url 要检查的URL
 * @return 是否为VPN URL
 */
fun isVpnUrl(url: String): Boolean {
    return try {
        val parsedUrl = URL(url)
        // 检查是否是d.buaa.edu.cn域名
                // 检查路径格式是否符合VPN URL模式
                parsedUrl.path.isNotEmpty() &&
                parsedUrl.path.substringAfter("/").contains("/")
    } catch (e: Exception) {
            log.warn("Invalid URL format: {}", url, e)
        false
    }
}

/**
 * 将普通URL转换为VPN URL
 * @param url 原始URL
 * @return VPN格式的URL
 */
fun toVpnUrl(url: String): String {
    try {
        val originalUrl = URL(url)
        if (originalUrl.host == "d.buaa.edu.cn") return url

        val protocol = when {
            originalUrl.port == -1 -> originalUrl.protocol
            originalUrl.protocol == "http" && originalUrl.port == 80 -> "http"
            originalUrl.protocol == "http" -> "http-${originalUrl.port}"
            originalUrl.protocol == "https" && originalUrl.port == 443 -> "https"
            originalUrl.protocol == "https" -> "https-${originalUrl.port}"
            originalUrl.protocol == "ws" && originalUrl.port == 80 -> "ws"
            originalUrl.protocol == "ws" -> "ws-${originalUrl.port}"
            originalUrl.protocol == "wss" && originalUrl.port == 443 -> "wss"
            originalUrl.protocol == "wss" -> "wss-${originalUrl.port}"
                else -> "${originalUrl.protocol}-${originalUrl.port}"
        }

        val path = originalUrl.path.ifEmpty { "/" }
        val query = originalUrl.query?.let { "?$it" } ?: ""
        val ref = originalUrl.ref?.let { "#$it" } ?: ""

        return "https://d.buaa.edu.cn/$protocol/${encrypt(originalUrl.host)}$path$query$ref"
    } catch (e: Exception) {
            log.warn("Failed to convert URL to VPN format: {}", url, e)
        return url
    }
}

/**
 * 将VPN URL转换为普通URL
 * @param vpnUrl VPN格式的URL
 * @return 原始URL
 */
fun toRawUrl(vpnUrl: String): String {
    try {
        val parsedUrl = URL(vpnUrl)
        if (parsedUrl.host != "d.buaa.edu.cn") return vpnUrl

        val pathParts = parsedUrl.path.removePrefix("/").split("/", limit = 3)
        if (pathParts.size < 2) return vpnUrl

        val protocol = pathParts[0]
        val encryptedHost = pathParts[1]
        val remainingPath = if (pathParts.size > 2) "/${pathParts[2]}" else "/"
        val query = parsedUrl.query?.let { "?$it" } ?: ""
        val ref = parsedUrl.ref?.let { "#$it" } ?: ""

        val (actualProtocol, port) = when {
            protocol.startsWith("http-") -> Pair("http", protocol.substringAfter("-"))
            protocol.startsWith("https-") -> Pair("https", protocol.substringAfter("-"))
            protocol.startsWith("ws-") -> Pair("ws", protocol.substringAfter("-"))
            protocol.startsWith("wss-") -> Pair("wss", protocol.substringAfter("-"))
            protocol == "http" -> Pair("http", "80")
            protocol == "https" -> Pair("https", "443")
            protocol == "ws" -> Pair("ws", "80")
            protocol == "wss" -> Pair("wss", "443")
            protocol.contains("-") -> {
                val parts = protocol.split("-", limit = 2)
                Pair(parts[0], parts[1])
            }
                else -> Pair(protocol, "")
        }

        val host = decrypt(encryptedHost)

        return if (port.isEmpty() ||
                (actualProtocol == "http" && port == "80") ||
                (actualProtocol == "https" && port == "443")) {
            "$actualProtocol://$host$remainingPath$query$ref"
        } else {
            "$actualProtocol://$host:$port$remainingPath$query$ref"
        }
    } catch (e: Exception) {
            log.warn("Failed to convert VPN URL to raw URL: {}", vpnUrl, e)
        return vpnUrl
    }
}
}
