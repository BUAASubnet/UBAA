package cn.edu.ubaa.api.auth

import io.ktor.http.Url

/** SSO 已启用 HSTS；原生客户端也必须将其旧 HTTP 跳转升级，保留 service 的原始编码。 */
internal fun secureCasTransportUrl(url: String): String {
  val parsed = Url(url)
  if (
      parsed.protocol.name == "http" &&
          parsed.host.equals("sso.buaa.edu.cn", ignoreCase = true) &&
          parsed.port == 80
  ) {
    return Regex("""^http://sso\.buaa\.edu\.cn(?::80)?(?=[/?#]|$)""", RegexOption.IGNORE_CASE)
        .replaceFirst(url, "https://sso.buaa.edu.cn")
  }
  return url
}
