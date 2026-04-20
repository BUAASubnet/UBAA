package cn.edu.ubaa.api

import io.ktor.http.Url

internal object LocalWebVpnSupport {
  private const val gatewayHost = "d.buaa.edu.cn"
  private const val keyText = "wrdvpnisthebest!"
  private val keyBytes = keyText.encodeToByteArray()
  private val ivBytes = keyText.encodeToByteArray()

  fun toWebVpnUrl(url: String): String {
    val parsed = runCatching { Url(url) }.getOrNull() ?: return url
    if (parsed.host.equals(gatewayHost, ignoreCase = true)) return url
    val protocolPart =
        when {
          parsed.specifiedPort == DEFAULT_HTTP_PORT && parsed.protocol.name == "http" -> "http"
          parsed.specifiedPort == DEFAULT_HTTPS_PORT && parsed.protocol.name == "https" -> "https"
          parsed.specifiedPort <= 0 -> parsed.protocol.name
          else -> "${parsed.protocol.name}-${parsed.specifiedPort}"
        }
    val encodedHost = encryptHost(parsed.host)
    val queryPart = parsed.encodedQuery.takeIf { it.isNotBlank() }?.let { "?$it" }.orEmpty()
    val fragmentPart = parsed.fragment.takeIf { it.isNotBlank() }?.let { "#$it" }.orEmpty()
    return "https://$gatewayHost/$protocolPart/$encodedHost${parsed.encodedPath}$queryPart$fragmentPart"
  }

  fun fromWebVpnUrl(url: String): String {
    val parsed = runCatching { Url(url) }.getOrNull() ?: return url
    if (!parsed.host.equals(gatewayHost, ignoreCase = true)) return url
    val segments = parsed.encodedPath.split('/').filter { it.isNotBlank() }
    if (segments.size < 2) return url
    val protocolPart = segments[0]
    val encodedHost = segments[1]
    val (scheme, port) =
        protocolPart.split('-', limit = 2).let { parts ->
          parts.firstOrNull().orEmpty() to parts.getOrNull(1)?.toIntOrNull()
        }
    if (scheme.isBlank()) return url
    val host = runCatching { decryptHost(encodedHost) }.getOrElse { return url }
    val authority =
        when (port) {
          null -> "$scheme://$host"
          else -> "$scheme://$host:$port"
        }
    val pathPart =
        if (segments.size > 2) {
          "/" + segments.drop(2).joinToString("/")
        } else {
          ""
        }
    val queryPart = parsed.encodedQuery.takeIf { it.isNotBlank() }?.let { "?$it" }.orEmpty()
    val fragmentPart = parsed.fragment.takeIf { it.isNotBlank() }?.let { "#$it" }.orEmpty()
    return "$authority$pathPart$queryPart$fragmentPart"
  }

  fun isSsoUrl(url: String?): Boolean {
    if (url.isNullOrBlank()) return false
    return fromWebVpnUrl(url).contains("sso.buaa.edu.cn", ignoreCase = true)
  }

  private fun encryptHost(host: String): String {
    val plain = host.encodeToByteArray()
    val padded = plain + ByteArray((16 - plain.size % 16) % 16) { '0'.code.toByte() }
    val cipherText = PlatformAesCfbNoPadding.encrypt(padded, keyBytes, ivBytes)
    return ivBytes.toHex() + cipherText.toHex().take(plain.size * 2)
  }

  private fun decryptHost(encodedHost: String): String {
    require(encodedHost.length >= 32) { "Invalid WebVPN host payload" }
    val iv = encodedHost.substring(0, 32).hexToBytes()
    val cipherHex =
        encodedHost.substring(32).let { text ->
          text + "0".repeat((32 - text.length % 32) % 32)
        }
    val decrypted =
        PlatformAesCfbNoPadding.decrypt(cipherHex.hexToBytes(), keyBytes, iv)
            .copyOf(encodedHost.length / 2 - 16)
    return decrypted.decodeToString()
  }

  private fun ByteArray.toHex(): String = joinToString("") { byte -> byte.toUByte().toString(16).padStart(2, '0') }

  private fun String.hexToBytes(): ByteArray =
      ByteArray(length / 2) { index ->
        ((this[index * 2].digitToInt(16) shl 4) or this[index * 2 + 1].digitToInt(16)).toByte()
      }

  private const val DEFAULT_HTTP_PORT = 80
  private const val DEFAULT_HTTPS_PORT = 443
}

internal fun localUpstreamUrl(url: String): String =
    when (ConnectionRuntime.currentMode()) {
      ConnectionMode.WEBVPN -> LocalWebVpnSupport.toWebVpnUrl(url)
      else -> url
    }

internal fun localIsSsoUrl(url: String?): Boolean = LocalWebVpnSupport.isSsoUrl(url)
