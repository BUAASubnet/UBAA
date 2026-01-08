package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.LoginRequest
import io.ktor.http.*
import org.jsoup.Jsoup
import org.slf4j.LoggerFactory

/** CAS/SSO 页面解析器。 专门负责解析统一身份认证相关的 HTML 内容，提取登录凭证、验证码标识，并根据页面结构构建 POST 表单参数。 */
object CasParser {
  private val log = LoggerFactory.getLogger(CasParser::class.java)

  /** 从登录页 HTML 中提取 execution 令牌。 该令牌是 CAS 流程中提交表单所必需的。 */
  fun extractExecution(html: String): String {
    val doc = Jsoup.parse(html)
    return doc.select("input[name=execution]").`val`().orEmpty()
  }

  /**
   * 检测登录页是否包含验证码配置信息。 解析页面中的 JavaScript 配置项 config.captcha。
   *
   * @param html 页面 HTML。
   * @param captchaUrlBase 验证码接口基准 URL。
   * @return 验证码信息对象，若不需要验证码则返回 null。
   */
  fun detectCaptcha(html: String, captchaUrlBase: String): CaptchaInfo? {
    try {
      val captchaPattern =
        Regex("""config\.captcha\s*=\s*\{\s*type:\s*['"]([^'"]+)['"],\s*id:\s*['"]([^'"]+)['"]""")
      val match = captchaPattern.find(html)

      if (match != null) {
        val type = match.groupValues[1]
        val id = match.groupValues[2]
        val imageUrl = "$captchaUrlBase?captchaId=$id"
        return CaptchaInfo(id = id, type = type, imageUrl = imageUrl)
      }
      return null
    } catch (e: Exception) {
      log.warn("Error detecting CAPTCHA from login page", e)
      return null
    }
  }

  /** 从 HTML 响应中寻找并提取登录失败的错误提示文字。 */
  fun findLoginError(html: String): String? {
    if (html.isBlank()) return null

    extractTipText(html)?.let {
      return it
    }

    return try {
      val doc = Jsoup.parse(html)
      val candidates =
        listOf(
          "div.alert.alert-danger#errorDiv p",
          "div.alert.alert-danger#errorDiv",
          "div.errors",
          "p.errors",
          "span.errors",
          ".tip-text",
        )

      candidates
        .asSequence()
        .map { sel -> doc.select(sel).text().trim() }
        .firstOrNull { it.isNotBlank() }
    } catch (e: Exception) {
      null
    }
  }

  /** 提取特定的 tip-text 错误容器中的内容。 */
  fun extractTipText(html: String): String? {
    val regex = Regex("""<div class=\"tip-text\">([^<]+)</div>""", RegexOption.IGNORE_CASE)
    return regex.find(html)?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.isNotBlank() }
  }

  /** 根据登录页面的实际表单结构构建提交参数。 会自动包含所有 hidden 字段和默认字段。 */
  fun buildCasLoginParameters(html: String, request: LoginRequest): Parameters {
    val doc = Jsoup.parse(html)
    val form =
      doc.selectFirst("form#fm1")
        ?: doc.selectFirst("form[action]")
        ?: return buildDefaultParameters(request, extractExecution(html))

    val inputs = form.select("input[name]")
    val presentNames = mutableSetOf<String>()

    return Parameters.build {
      for (input in inputs) {
        val name = input.attr("name").trim()
        if (name.isBlank()) continue
        val type = input.attr("type").trim().lowercase()
        val value = input.`val`()

        if (name == "username" || name == "password") {
          presentNames.add(name)
          continue
        }

        when (type) {
          "submit",
          "button",
          "image" -> {}
          "checkbox" -> {
            presentNames.add(name)
            if (input.hasAttr("checked")) append(name, value.ifBlank { "on" })
          }
          "hidden" -> {
            presentNames.add(name)
            append(name, value)
          }
          else -> {
            presentNames.add(name)
            if (value.isNotBlank()) append(name, value)
          }
        }
      }

      append("username", request.username)
      append("password", request.password)
      append("submit", "登录")

      request.captcha
        ?.takeIf { it.isNotBlank() }
        ?.let { captchaValue ->
          if (inputs.any { it.attr("name") == "captcha" }) append("captcha", captchaValue)
          if (inputs.any { it.attr("name") == "captchaResponse" })
            append("captchaResponse", captchaValue)
        }

      if (!presentNames.contains("_eventId")) append("_eventId", "submit")
    }
  }

  /** 构建包含验证码的固定格式登录参数。 */
  fun buildCaptchaLoginParameters(request: LoginRequest): Parameters {
    val captcha = request.captcha ?: ""
    val execution = request.execution ?: ""

    return Parameters.build {
      append("username", request.username)
      append("password", request.password)
      append("captcha", captcha)
      append("execution", execution)
      append("_eventId", "submit")
      append("submit", "登录")
      append("type", "username_password")
    }
  }

  /** 构建基础的默认登录参数。 */
  fun buildDefaultParameters(request: LoginRequest, execution: String): Parameters {
    return Parameters.build {
      append("username", request.username)
      append("password", request.password)
      append("submit", "登录")
      append("type", "username_password")
      append("execution", execution)
      append("_eventId", "submit")
    }
  }
}
