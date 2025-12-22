package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.LoginRequest
import io.ktor.http.*
import org.jsoup.Jsoup
import org.slf4j.LoggerFactory

/** 专门负责解析 SSO/CAS 相关的 HTML 内容、提取 Token 和构建表单参数。 */
object CasParser {
    private val log = LoggerFactory.getLogger(CasParser::class.java)

    /** 从登录页 HTML 提取 execution token。 */
    fun extractExecution(html: String): String {
        val doc = Jsoup.parse(html)
        return doc.select("input[name=execution]").`val`().orEmpty()
    }

    /** 检测登录页是否包含验证码配置。 */
    fun detectCaptcha(html: String, captchaUrlBase: String): CaptchaInfo? {
        try {
            val captchaPattern =
                    Regex(
                            """config\.captcha\s*=\s*\{\s*type:\s*['"]([^'"]+)['"],\s*id:\s*['"]([^'"]+)['"]"""
                    )
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

    /** 从响应体中解析登录错误消息。 */
    fun findLoginError(html: String): String? {
        if (html.isBlank()) return null

        // 优先提取 tip-text
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
                            ".tip-text"
                    )

            candidates.asSequence().map { sel -> doc.select(sel).text().trim() }.firstOrNull {
                it.isNotBlank()
            }
        } catch (e: Exception) {
            null
        }
    }

    /** 提取 tip-text 错误提示。 */
    fun extractTipText(html: String): String? {
        val regex = Regex("""<div class=\"tip-text\">([^<]+)</div>""", RegexOption.IGNORE_CASE)
        return regex.find(html)?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.isNotBlank() }
    }

    /** 构建 CAS 登录表单参数。 */
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
                    "submit", "button", "image" -> {}
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

            request.captcha?.takeIf { it.isNotBlank() }?.let { captchaValue ->
                if (inputs.any { it.attr("name") == "captcha" }) append("captcha", captchaValue)
                if (inputs.any { it.attr("name") == "captchaResponse" })
                        append("captchaResponse", captchaValue)
            }

            if (!presentNames.contains("_eventId")) append("_eventId", "submit")
        }
    }

    /** 构建验证码登录的表单参数。 */
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

    private fun buildDefaultParameters(request: LoginRequest, execution: String): Parameters {
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
