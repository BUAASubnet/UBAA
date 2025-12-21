package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.LoginPreloadResponse
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.LoginResponse
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfoResponse
import cn.edu.ubaa.utils.JwtUtil
import io.ktor.client.HttpClient
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import java.time.Duration
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.jsoup.Jsoup
import org.slf4j.LoggerFactory

class AuthService(private val sessionManager: SessionManager = GlobalSessionManager.instance) {

    private val log = LoggerFactory.getLogger(AuthService::class.java)
    private val GENERIC_LOGIN_ERROR = "出了点问题，请检查用户名和密码，或稍后重试"

    private fun failLogin(reason: String? = null): Nothing {
        reason?.let { log.warn("Login failed detail: {}", it) }
        throw LoginException(GENERIC_LOGIN_ERROR)
    }

    /** 登录并返回用户数据及 JWT Token */
    suspend fun loginWithToken(request: LoginRequest): LoginResponse {
        log.info("Starting login process with JWT for user: {}", request.username)
        log.debug(
                "Login request - captcha: {}, execution: {}, clientId: {}",
                request.captcha?.take(10) ?: "null",
                request.execution?.take(10) ?: "null",
                request.clientId ?: "null"
        )

        // 检查是否有 clientId（来自 preload 的会话）
        val hasClientId = !request.clientId.isNullOrBlank()
        // 只有同时携带 execution 与 captcha 时才视为“验证码登录表单”
        val hasCaptchaForm = !request.execution.isNullOrBlank() && !request.captcha.isNullOrBlank()

        log.debug("hasClientId: {}, hasCaptchaForm: {}", hasClientId, hasCaptchaForm)

        // 如果没有 clientId 且没有验证码表单，检查已有会话
        if (!hasClientId && !hasCaptchaForm) {
            sessionManager.getSession(request.username)?.let { existingSession ->
                log.debug("Validating cached session for user: {}", request.username)
                val cachedUser = runCatching { verifySession(existingSession.client) }.getOrNull()
                if (cachedUser != null) {
                    log.info("Reusing cached session for user: {}", request.username)
                    val newToken = JwtUtil.generateToken(request.username, Duration.ofMinutes(30))
                    return LoginResponse(cachedUser, newToken)
                }
                log.info(
                        "Cached session for user {} is invalid. Re-authenticating.",
                        request.username
                )
                sessionManager.invalidateSession(request.username)
            }
        }

        // 准备会话：优先使用 clientId 对应的预登录会话
        val sessionCandidate =
                if (hasClientId) {
                    // 尝试复用预登录会话
                    sessionManager.promotePreLoginSession(request.clientId!!, request.username)
                            ?: run {
                                log.warn(
                                        "PreLogin session for clientId {} not found or expired, creating new session",
                                        request.clientId
                                )
                                sessionManager.prepareSession(request.username)
                            }
                } else {
                    // 清理可能存在的旧 cookies
                    sessionManager.invalidateSession(request.username)
                    sessionManager.prepareSession(request.username)
                }

        val client = sessionCandidate.client
        val noRedirectClient = client.config { followRedirects = false }

        // 如果携带 execution+captcha，走验证码登录表单分支
        if (hasCaptchaForm) {
            val execution = request.execution ?: throw LoginException("execution is missing")
            val captcha = request.captcha ?: throw LoginException("验证码缺失，请重新输入")

            log.debug("Direct login with execution={}", execution.take(10))

            // 直接使用用户提供的 execution 和 captcha 构建登录表单
            // 注意：cookies 从数据库加载（第一次登录时保存的）
            val loginFormParameters =
                    buildCaptchaLoginParameters(
                            request.copy(captcha = captcha, execution = execution)
                    )

            val loginSubmitResponse =
                    noRedirectClient.post(LOGIN_URL) {
                        setBody(FormDataContent(loginFormParameters))
                    }

            log.debug(
                    "CAPTCHA login form submitted. Response status: {}",
                    loginSubmitResponse.status
            )

            // 手动跟随 302 重定向
            // 登录成功时 SSO 返回 302，失败时返回 200 或 401
            if (loginSubmitResponse.status == HttpStatusCode.Found) {
                var redirectResponse = loginSubmitResponse
                while (redirectResponse.status == HttpStatusCode.Found) {
                    val location = redirectResponse.headers[HttpHeaders.Location]
                    if (location.isNullOrBlank()) break
                    log.debug("Following redirect to: {}", location)
                    redirectResponse = noRedirectClient.get(location)
                }
            } else if (loginSubmitResponse.status == HttpStatusCode.Unauthorized) {
                val bodyText = runCatching { loginSubmitResponse.bodyAsText() }.getOrNull()
                val tip = bodyText?.let { extractTipText(it) }
                client.close()
                failLogin(tip ?: "验证码错误或已过期")
            } else if (loginSubmitResponse.status == HttpStatusCode.OK) {
                // 登录失败时 SSO 通常返回 200 + 错误页面
                val bodyText = runCatching { loginSubmitResponse.bodyAsText() }.getOrNull()
                val tip = bodyText?.let { extractTipText(it) }

                // 检查是否有任何错误提示（使用已读取的 bodyText）
                val errorMessage = tip ?: bodyText?.let { findLoginErrorFromBody(it) }
                if (errorMessage != null) {
                    client.close()
                    failLogin(errorMessage)
                }

                // 如果返回 200 但没有错误提示，可能是验证码错误或其他问题
                // 检查页面中是否仍有登录表单（表示登录未成功）
                if (bodyText?.contains("input name=\"execution\"") == true ||
                                bodyText?.contains("config.captcha") == true
                ) {
                    client.close()
                    failLogin("验证码错误或密码错误")
                }
            } else {
                // 其他状态码
                val bodyText = runCatching { loginSubmitResponse.bodyAsText() }.getOrNull()
                val errorMessage = bodyText?.let { findLoginErrorFromBody(it) }
                if (errorMessage != null) {
                    client.close()
                    failLogin(errorMessage)
                }
            }
        } else {
            // 普通登录流程：获取 execution token
            val loginPageResponse = noRedirectClient.get(LOGIN_URL)
            if (loginPageResponse.status != HttpStatusCode.OK) {
                log.error("Failed to load login page. Status: {}", loginPageResponse.status)
                client.close()
                failLogin("load login page status=${loginPageResponse.status}")
            }
            val loginPageHtml = loginPageResponse.bodyAsText()
            val doc = Jsoup.parse(loginPageHtml)

            // Python 逻辑同款：如果登录页已给出 tip-text 直接返回提示（多见于密码错误）
            extractTipText(loginPageHtml)?.let { tip ->
                client.close()
                failLogin(tip)
            }

            // 存在 execution 则提交凭证，否则视为已在 SSO 登录
            val execution = doc.select("input[name=execution]").`val`().orEmpty()
            log.debug("Got execution token: {}...", execution.take(10))

            if (execution.isNotBlank()) {
                val casForm = doc.selectFirst("form#fm1") ?: doc.selectFirst("form[action]")

                // 检查是否有验证码
                val captchaInfo = detectCaptcha(loginPageHtml)
                if (captchaInfo != null) {
                    log.debug(
                            "CAPTCHA detected in login page. request.captcha.isNullOrBlank()={}",
                            request.captcha.isNullOrBlank()
                    )
                    if (request.captcha.isNullOrBlank()) {
                        log.info("CAPTCHA required for user: {}", request.username)

                        // 重要：使用当前会话的 cookies 获取验证码图片并转为 base64
                        // 这样客户端就不需要单独请求验证码图片了
                        val captchaImageBytes = getCaptchaImage(client, captchaInfo.id)
                        val base64Image =
                                captchaImageBytes?.let {
                                    "data:image/jpeg;base64," +
                                            java.util.Base64.getEncoder().encodeToString(it)
                                }

                        // 创建包含 base64 图片的 CaptchaInfo
                        val captchaInfoWithImage = captchaInfo.copy(base64Image = base64Image)

                        // 关闭 client 以释放资源，但 cookies 已保存在 SqliteCookieStorage 中
                        // 客户端再次提交时会加载这些 cookies
                        client.close()
                        // 抛出异常，返回当前 session 的验证码信息和 execution
                        // 客户端需要用这些信息再次提交登录
                        throw CaptchaRequiredException(captchaInfoWithImage, execution)
                    }
                    // 用户提供了验证码，使用当前 session 的 execution 提交
                    // 注意：SSO 表单不需要 captchaId 字段，只需要 captcha（用户输入的验证码值）
                    log.info(
                            "CAPTCHA provided by user, submitting with current session's execution"
                    )
                    val loginFormParameters =
                            Parameters.build {
                                append("username", request.username)
                                append("password", request.password)
                                append("captcha", request.captcha!!)
                                append("execution", execution)
                                append("_eventId", "submit")
                                append("submit", "登录")
                                append("type", "username_password")
                            }

                    val loginSubmitResponse =
                            noRedirectClient.post(LOGIN_URL) {
                                setBody(FormDataContent(loginFormParameters))
                            }

                    log.debug(
                            "CAPTCHA login form submitted. Response status: {}",
                            loginSubmitResponse.status
                    )

                    // 手动跟随 302 重定向
                    if (loginSubmitResponse.status == HttpStatusCode.Found) {
                        var redirectResponse = loginSubmitResponse
                        while (redirectResponse.status == HttpStatusCode.Found) {
                            val location = redirectResponse.headers[HttpHeaders.Location]
                            if (location.isNullOrBlank()) break
                            log.debug("Following redirect to: {}", location)
                            redirectResponse = noRedirectClient.get(location)
                        }
                    }

                    if (loginSubmitResponse.status == HttpStatusCode.Unauthorized) {
                        val bodyText = runCatching { loginSubmitResponse.bodyAsText() }.getOrNull()
                        val tip = bodyText?.let { extractTipText(it) }
                        client.close()
                        failLogin(tip ?: "验证码错误或密码错误")
                    }

                    // 处理其他状态码（包括 200）
                    val bodyText = runCatching { loginSubmitResponse.bodyAsText() }.getOrNull()
                    val errorMessage = bodyText?.let { findLoginErrorFromBody(it) }
                    if (errorMessage != null) {
                        client.close()
                        failLogin(errorMessage)
                    }

                    // 检查是否仍在登录页面（表示登录失败）
                    if (loginSubmitResponse.status == HttpStatusCode.OK &&
                                    (bodyText?.contains("input name=\"execution\"") == true ||
                                            bodyText?.contains("config.captcha") == true)
                    ) {
                        client.close()
                        failLogin("验证码错误或密码错误")
                    }
                } else {
                    // 不需要验证码，使用普通登录流程
                    // 2. 提交登录凭证
                    val loginFormParameters =
                            if (casForm != null) {
                                buildCasLoginParameters(casForm, request)
                            } else {
                                Parameters.build {
                                    append("username", request.username)
                                    append("password", request.password)
                                    append("submit", "登录")
                                    append("type", "username_password")
                                    append("execution", execution)
                                    append("_eventId", "submit")
                                }
                            }

                    val loginSubmitResponse =
                            noRedirectClient.post(LOGIN_URL) {
                                // 禁止自动重定向，便于保留原始响应体解析错误提示
                                setBody(FormDataContent(loginFormParameters))
                            }

                    log.debug(
                            "Login form submitted. Response status: {}",
                            loginSubmitResponse.status
                    )

                    // 手动跟随 302 重定向（参考 Python 版本）
                    if (loginSubmitResponse.status == HttpStatusCode.Found) {
                        var redirectResponse = loginSubmitResponse
                        while (redirectResponse.status == HttpStatusCode.Found) {
                            val location = redirectResponse.headers[HttpHeaders.Location]
                            if (location.isNullOrBlank()) break
                            log.debug("Following redirect to: {}", location)
                            redirectResponse = noRedirectClient.get(location)
                        }
                    }

                    // 读取响应体一次
                    val bodyText = runCatching { loginSubmitResponse.bodyAsText() }.getOrNull()

                    // 若 SSO 直接返回 401，通常为密码错误或账号限制，优先解析提示
                    if (loginSubmitResponse.status == HttpStatusCode.Unauthorized) {
                        val tip = bodyText?.let { extractTipText(it) }
                        client.close()
                        failLogin(tip ?: "账号或密码错误")
                    }

                    // 检查响应体中的错误信息
                    val errorMessage = bodyText?.let { findLoginErrorFromBody(it) }
                    if (errorMessage != null) {
                        client.close()
                        failLogin(errorMessage)
                    }
                }
            } else {
                log.info("No execution token found. Assuming already logged in at SSO.")
            }
        }

        // 3. 触发 UC 服务登录（建立 UC 会话的关键步骤）
        log.debug("Triggering UC service login...")
        client.get(
                "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
        )

        try {
            val userData = verifySession(client)
            if (userData != null) {
                // 初始化博雅会话以访问课表
                initializeByxtSession(client)

                val sessionWithToken =
                        sessionManager.commitSessionWithToken(sessionCandidate, userData)
                log.info("Session verified successfully for user: {} with JWT", request.username)
                return LoginResponse(userData, sessionWithToken.jwtToken)
            }

            log.error(
                    "Session verification failed for user: {}. Status API returned non-OK status or invalid body.",
                    request.username
            )

            client.close()
            failLogin("session verification failed")
        } catch (e: LoginException) {
            throw e
        } catch (e: Exception) {
            client.close()
            log.error("Error while verifying session for user: {}", request.username, e)
            failLogin("session verification exception ${e.message}")
        }
    }

    /** 调用 BUAA SSO 注销接口并销毁本地会话。 */
    suspend fun logout(username: String) {
        log.info("Starting logout process for user: {}", username)

        val session = sessionManager.getSession(username)
        if (session != null) {
            try {
                val logoutResponse = session.client.get("https://sso.buaa.edu.cn/logout")
                log.debug("SSO logout response status: {}", logoutResponse.status)
            } catch (e: Exception) {
                log.warn("Error calling BUAA SSO logout for user: {}", username, e)
            }

            sessionManager.invalidateSession(username)
            log.info("Session invalidated successfully for user: {}", username)
        } else {
            log.warn("No active session found for user: {}", username)
        }
    }

    /** 预加载登录状态：为 clientId 创建专属会话，访问 SSO 登录页面，获取验证码（如果需要） */
    suspend fun preloadLoginState(clientId: String): LoginPreloadResponse {
        require(clientId.isNotBlank()) { "clientId is required" }
        log.info("Preloading login state for clientId: {}", clientId)

        // 为该 clientId 创建或复用预登录会话
        val preLoginCandidate = sessionManager.preparePreLoginSession(clientId)
        val client = preLoginCandidate.client

        return try {
            val loginPageResponse = client.get(LOGIN_URL)
            if (loginPageResponse.status != HttpStatusCode.OK) {
                log.error(
                        "Failed to load login page for preload. Status: {}",
                        loginPageResponse.status
                )
                return LoginPreloadResponse(captchaRequired = false, clientId = clientId)
            }

            val loginPageHtml = loginPageResponse.bodyAsText()

            // 获取 execution token
            val doc = Jsoup.parse(loginPageHtml)
            val execution = doc.select("input[name=execution]").`val`().orEmpty()

            // 检测是否需要验证码
            val captchaInfo = detectCaptcha(loginPageHtml)

            if (captchaInfo != null) {
                log.info("Preload: CAPTCHA required for clientId: {}", clientId)

                // 使用当前会话获取验证码图片并转为 base64
                val captchaImageBytes = getCaptchaImage(client, captchaInfo.id)
                val base64Image =
                        captchaImageBytes?.let {
                            "data:image/jpeg;base64," +
                                    java.util.Base64.getEncoder().encodeToString(it)
                        }

                val captchaInfoWithImage = captchaInfo.copy(base64Image = base64Image)

                LoginPreloadResponse(
                        captchaRequired = true,
                        captcha = captchaInfoWithImage,
                        execution = execution,
                        clientId = clientId
                )
            } else {
                log.info("Preload: No CAPTCHA required for clientId: {}", clientId)
                LoginPreloadResponse(
                        captchaRequired = false,
                        execution = execution.takeIf { it.isNotBlank() },
                        clientId = clientId
                )
            }
        } catch (e: Exception) {
            log.warn("Failed to preload login state for clientId {}: {}", clientId, e.message)
            // 出错时清理预登录会话
            sessionManager.cleanupPreLoginSession(clientId)
            LoginPreloadResponse(captchaRequired = false, clientId = clientId)
        }
    }

    private suspend fun verifySession(client: HttpClient): UserData? {
        log.debug("Verifying session by accessing https://uc.buaa.edu.cn/api/uc/status")
        val statusResponse =
                client.get(UC_STATUS_URL) {
                    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
                    header("X-Requested-With", "XMLHttpRequest")
                    header(HttpHeaders.Referrer, "https://uc.buaa.edu.cn/#/user/login")
                }
        val statusBody = statusResponse.bodyAsText()
        log.debug("Status API response status: {}", statusResponse.status)
        log.debug("Status API response body (truncated): {}", statusBody.take(200))

        if (statusResponse.status != HttpStatusCode.OK) return null

        val trimmedBody = statusBody.trimStart()
        if (!trimmedBody.startsWith("{") && !trimmedBody.startsWith("[")) {
            log.warn("Status API returned non-JSON payload, likely indicating SSO redirect.")
            return null
        }

        return try {
            val userInfoResponse = Json.decodeFromString<UserInfoResponse>(statusBody)
            if (userInfoResponse.code == 0) {
                val userInfo = userInfoResponse.data ?: return null
                UserData(name = userInfo.name.orEmpty(), schoolid = userInfo.schoolid.orEmpty())
            } else {
                val err =
                        when (userInfoResponse.code) {
                            10600 -> "登录失败：账号或密码错误"
                            else -> "登录失败：状态接口返回 code=${userInfoResponse.code}"
                        }
                failLogin(err)
            }
        } catch (e: Exception) {
            log.error("Failed to parse user info from status API response.", e)
            null
        }
    }

    /** 初始化BYXT会话。 流程：访问 index.do -> 跳转 SSO -> SSO 回调带 ticket -> BYXT 验证 ticket 并设 Cookie。 */
    private suspend fun initializeByxtSession(client: HttpClient) {
        log.debug("Initializing BYXT session via SSO")
        try {
            // 关键是访问 index.do 以触发 SSO 流程
            // Ktor 自动跟随重定向，包括携带 ticket 的 SSO 重定向
            val byxtIndexUrl = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do"

            log.debug("Step 1: Accessing BYXT index.do to trigger SSO authentication")
            val byxtResponse = client.get(byxtIndexUrl)
            log.debug("BYXT index.do response status: {}", byxtResponse.status)

            // 返回 200 OK 表示 SSO 认证成功
            if (byxtResponse.status == HttpStatusCode.OK) {
                val body = byxtResponse.bodyAsText()
                // 检查是否获取到实际页面内容（非登录页）
                if (body.contains("homeapp") || body.contains("首页") || body.length > 1000) {
                    log.info("BYXT session initialized successfully via SSO redirect flow")

                    // 可选：调用 API 验证
                    val apiUrl =
                            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getUserInfo.do"
                    val apiResponse =
                            client.get(apiUrl) {
                                header(
                                        HttpHeaders.Accept,
                                        "application/json, text/javascript, */*; q=0.01"
                                )
                                header("X-Requested-With", "XMLHttpRequest")
                                header(HttpHeaders.Referrer, byxtIndexUrl)
                            }
                    val apiBody = apiResponse.bodyAsText()
                    log.debug(
                            "BYXT API verification response: status={}, body={}",
                            apiResponse.status,
                            apiBody.take(200)
                    )

                    if (apiResponse.status == HttpStatusCode.OK &&
                                    apiBody.contains("\"code\":\"0\"")
                    ) {
                        log.info("BYXT API access verified successfully")
                    } else {
                        log.warn("BYXT API verification returned unexpected response")
                    }
                } else {
                    log.warn("BYXT index.do returned 200 but content looks like a login page")
                    log.debug("Response body (first 500 chars): {}", body.take(500))
                }
            } else {
                log.warn("BYXT index.do returned unexpected status: {}", byxtResponse.status)
            }
        } catch (e: Exception) {
            log.error("Failed to initialize BYXT session", e)
            // 不抛出异常 - BYXT 初始化失败不应阻塞登录
        }
    }

    companion object {
        // Reverted to simple login URL without service parameter to match working legacy flow
        private const val LOGIN_URL: String = "https://sso.buaa.edu.cn/login"
        private const val UC_STATUS_URL = "https://uc.buaa.edu.cn/api/uc/status"
        private const val CAPTCHA_URL_BASE = "https://sso.buaa.edu.cn/captcha"
    }

    private suspend fun findLoginError(response: HttpResponse): String? {
        val responseBody = runCatching { response.bodyAsText() }.getOrNull() ?: return null
        return findLoginErrorFromBody(responseBody)
    }

    /** 从响应体字符串中解析登录错误消息 */
    private fun findLoginErrorFromBody(responseBody: String): String? {
        if (responseBody.isBlank()) return null

        // 优先复用 tip-text 文案（与 Python 逻辑保持一致）
        extractTipText(responseBody)?.let {
            return it
        }

        return try {
            val doc = Jsoup.parse(responseBody)
            val candidates =
                    listOf(
                            "div.alert.alert-danger#errorDiv p",
                            "div.alert.alert-danger#errorDiv",
                            "div.errors",
                            "p.errors",
                            "span.errors",
                            ".tip-text"
                    )

            val errorText =
                    candidates
                            .asSequence()
                            .map { sel -> doc.select(sel).text().trim() }
                            .firstOrNull { it.isNotBlank() }

            errorText
        } catch (e: Exception) {
            log.debug("Failed to parse login error message from CAS response.", e)
            null
        }
    }

    /** 从登录页 HTML 提取 tip-text 错误提示。 */
    private fun extractTipText(html: String): String? {
        val regex = Regex("""<div class=\"tip-text\">([^<]+)</div>""", RegexOption.IGNORE_CASE)
        return regex.find(html)?.groupValues?.getOrNull(1)?.trim()?.takeIf { it.isNotBlank() }
    }

    private fun buildCasLoginParameters(
            form: org.jsoup.nodes.Element,
            request: LoginRequest
    ): Parameters {
        val inputs = form.select("input[name]")
        val presentNames = mutableSetOf<String>()

        val built =
                Parameters.build {
                    for (input in inputs) {
                        val name = input.attr("name").trim()
                        if (name.isBlank()) continue
                        val type = input.attr("type").trim().lowercase()
                        val value = input.`val`()

                        // 下文显式覆盖
                        if (name == "username" || name == "password") {
                            presentNames.add(name)
                            continue
                        }

                        when (type) {
                            "submit", "button", "image" -> {
                                // 忽略
                            }
                            "checkbox" -> {
                                presentNames.add(name)
                                if (input.hasAttr("checked")) {
                                    append(name, value.ifBlank { "on" })
                                }
                            }
                            "hidden" -> {
                                presentNames.add(name)
                                // 隐藏字段通常必填
                                append(name, value)
                            }
                            else -> {
                                presentNames.add(name)
                                if (value.isNotBlank()) {
                                    append(name, value)
                                }
                            }
                        }
                    }

                    append("username", request.username)
                    append("password", request.password)
                    append("submit", "登录")

                    // 验证码字段名可能变化，尽力适配
                    request.captcha?.takeIf { it.isNotBlank() }?.let { captchaValue ->
                        if (inputs.any { it.attr("name") == "captcha" })
                                append("captcha", captchaValue)
                        if (inputs.any { it.attr("name") == "captchaResponse" }) {
                            append("captchaResponse", captchaValue)
                        }
                    }

                    // 确保 event id 存在
                    if (!presentNames.contains("_eventId")) {
                        append("_eventId", "submit")
                    }
                }

        return built
    }

    /** 构建验证码登录的表单参数（不依赖 HTML 表单解析） */
    private fun buildCaptchaLoginParameters(request: LoginRequest): Parameters {
        // 注意：SSO 表单不需要 captchaId 字段，只需要 captcha（用户输入的验证码值）
        // 正确的表单格式：username=***&password=***&captcha=xxx&submit=登录&type=username_password&execution=***&_eventId=submit
        val captcha = request.captcha ?: throw LoginException("验证码缺失，请重新输入")
        val execution = request.execution ?: throw LoginException("execution is missing")

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

    /** 检测登录页是否包含验证码配置。 */
    private fun detectCaptcha(loginPageHtml: String): CaptchaInfo? {
        try {
            // 查找 JS 配置模式：config.captcha = { type: 'image', id: '...' };
            val captchaPattern =
                    Regex(
                            """config\.captcha\s*=\s*\{\s*type:\s*['"]([^'"]+)['"],\s*id:\s*['"]([^'"]+)['"]"""
                    )
            val match = captchaPattern.find(loginPageHtml)

            if (match != null) {
                val type = match.groupValues[1]
                val id = match.groupValues[2]
                val imageUrl = "$CAPTCHA_URL_BASE?captchaId=$id"

                log.debug("Detected CAPTCHA: type={}, id={}, imageUrl={}", type, id, imageUrl)
                return CaptchaInfo(id = id, type = type, imageUrl = imageUrl)
            }

            log.debug("No CAPTCHA detected in login page")
            return null
        } catch (e: Exception) {
            log.warn("Error detecting CAPTCHA from login page", e)
            return null
        }
    }

    /** 获取验证码图片数据。 */
    suspend fun getCaptchaImage(client: HttpClient, captchaId: String): ByteArray? {
        return try {
            log.debug("Fetching CAPTCHA image for id: {}", captchaId)
            val response = client.get("$CAPTCHA_URL_BASE?captchaId=$captchaId")
            if (response.status == HttpStatusCode.OK) {
                response.body<ByteArray>()
            } else {
                log.warn("Failed to fetch CAPTCHA image. Status: {}", response.status)
                null
            }
        } catch (e: Exception) {
            log.error("Error fetching CAPTCHA image", e)
            null
        }
    }
}

class LoginException(message: String) : Exception(message)

class CaptchaRequiredException(
        val captchaInfo: CaptchaInfo,
        val execution: String,
        message: String = "CAPTCHA verification required"
) : Exception(message)
