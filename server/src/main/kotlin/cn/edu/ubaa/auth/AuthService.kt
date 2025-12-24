package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.LoginPreloadResponse
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.LoginResponse
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfoResponse
import cn.edu.ubaa.utils.JwtUtil
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.HttpClient
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import java.time.Duration
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
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
        // 检查是否携带了 execution（可能来自 preload）
        val hasExecution = !request.execution.isNullOrBlank()
        // 只有同时携带 execution 与 captcha 时才视为“验证码登录表单”
        val hasCaptchaForm = hasExecution && !request.captcha.isNullOrBlank()

        log.debug(
                "hasClientId: {}, hasExecution: {}, hasCaptchaForm: {}",
                hasClientId,
                hasExecution,
                hasCaptchaForm
        )

        // 如果没有 clientId 且没有 execution，检查已有会话
        if (!hasClientId && !hasExecution) {
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
                                // 即使 promote 失败，也要确保 username 的旧会话被清理
                                sessionManager.invalidateSession(request.username)
                                sessionManager.prepareSession(request.username)
                            }
                } else {
                    // 清理可能存在的旧 cookies
                    sessionManager.invalidateSession(request.username)
                    sessionManager.prepareSession(request.username)
                }

        val client = sessionCandidate.client
        val noRedirectClient = client.config { followRedirects = false }

        // 如果携带 execution，尝试直接提交（减少一次 GET 请求，提高稳定性）
        if (hasExecution) {
            val execution = request.execution!!
            log.debug("Direct login with provided execution={}", execution.take(10))

            val loginFormParameters =
                    if (!request.captcha.isNullOrBlank()) {
                        CasParser.buildCaptchaLoginParameters(request)
                    } else {
                        CasParser.buildDefaultParameters(request, execution)
                    }

            val loginSubmitResponse =
                    noRedirectClient.post(LOGIN_URL) {
                        setBody(FormDataContent(loginFormParameters))
                    }

            log.debug(
                    "Login form submitted with provided execution. Response status: {}",
                    loginSubmitResponse.status
            )

            // 手动跟随重定向并检查错误
            followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient, client)
        } else {
            // 普通登录流程：获取 execution token
            val loginPageResponse = noRedirectClient.get(LOGIN_URL)
            if (loginPageResponse.status != HttpStatusCode.OK &&
                            loginPageResponse.status != HttpStatusCode.Found &&
                            loginPageResponse.status != HttpStatusCode.MovedPermanently &&
                            loginPageResponse.status != HttpStatusCode.SeeOther
            ) {
                log.error("Failed to load login page. Status: {}", loginPageResponse.status)
                client.close()
                failLogin("load login page status=${loginPageResponse.status}")
            }
            val loginPageHtml = loginPageResponse.bodyAsText()

            // 如果登录页已给出 tip-text 直接返回提示
            CasParser.extractTipText(loginPageHtml)?.let { tip ->
                client.close()
                failLogin(tip)
            }

            // 存在 execution 则提交凭证，否则视为已在 SSO 登录
            val execution = CasParser.extractExecution(loginPageHtml)
            log.debug("Got execution token: {}...", execution.take(10))

            if (execution.isNotBlank()) {
                // 检查是否有验证码
                val captchaInfo = CasParser.detectCaptcha(loginPageHtml, CAPTCHA_URL_BASE)
                if (captchaInfo != null) {
                    if (request.captcha.isNullOrBlank()) {
                        log.info("CAPTCHA required for user: {}", request.username)
                        val captchaImageBytes = getCaptchaImage(client, captchaInfo.id)
                        val base64Image =
                                captchaImageBytes?.let {
                                    "data:image/jpeg;base64," +
                                            java.util.Base64.getEncoder().encodeToString(it)
                                }
                        val captchaInfoWithImage = captchaInfo.copy(base64Image = base64Image)
                        client.close()
                        throw CaptchaRequiredException(captchaInfoWithImage, execution)
                    }
                    // 用户提供了验证码
                    log.info(
                            "CAPTCHA provided by user, submitting with current session's execution"
                    )
                    val loginFormParameters = CasParser.buildCaptchaLoginParameters(request)

                    val loginSubmitResponse =
                            noRedirectClient.post(LOGIN_URL) {
                                setBody(FormDataContent(loginFormParameters))
                            }

                    // 手动跟随重定向并检查错误
                    followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient, client)
                } else {
                    // 不需要验证码，使用普通登录流程
                    val loginFormParameters =
                            CasParser.buildCasLoginParameters(loginPageHtml, request)

                    val loginSubmitResponse =
                            noRedirectClient.post(LOGIN_URL) {
                                setBody(FormDataContent(loginFormParameters))
                            }

                    // 手动跟随重定向并检查错误
                    followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient, client)
                }
            } else {
                log.info("No execution token found. Assuming already logged in at SSO.")
            }
        }

        // 3. 触发 UC 服务登录（建立 UC 会话的关键步骤）
        log.debug("Triggering UC service login...")
        client.get(
                VpnCipher.toVpnUrl(
                        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
                )
        )

        try {
            val userData = verifySession(client)
            if (userData != null) {
                // 初始化博雅会话
                ByxtService.initializeSession(client)

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
                val logoutResponse =
                        session.client.get(VpnCipher.toVpnUrl("https://sso.buaa.edu.cn/logout"))
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
        val noRedirectClient = client.config { followRedirects = false }

        return try {
            val loginPageResponse = noRedirectClient.get(LOGIN_URL)

            // 如果是重定向，说明 SSO 会话可能已经处于登录状态
            if (loginPageResponse.status == HttpStatusCode.Found ||
                            loginPageResponse.status == HttpStatusCode.MovedPermanently ||
                            loginPageResponse.status == HttpStatusCode.SeeOther
            ) {
                val location = loginPageResponse.headers[HttpHeaders.Location]
                log.info("Preload: Already logged in at SSO (redirected to {})", location)

                // 触发 UC 服务登录以建立 UC 会话
                client.get(
                        VpnCipher.toVpnUrl(
                                "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
                        )
                )

                val userData = verifySession(client)
                if (userData != null && !userData.schoolid.isNullOrBlank()) {
                    log.info("Preload: Auto-login successful for user: {}", userData.schoolid)
                    // 迁移预登录会话到正式会话
                    val sessionCandidate =
                            sessionManager.promotePreLoginSession(clientId, userData.schoolid)
                    if (sessionCandidate != null) {
                        // 初始化博雅会话
                        ByxtService.initializeSession(sessionCandidate.client)
                        val sessionWithToken =
                                sessionManager.commitSessionWithToken(sessionCandidate, userData)
                        return LoginPreloadResponse(
                                captchaRequired = false,
                                clientId = clientId,
                                token = sessionWithToken.jwtToken,
                                userData = userData
                        )
                    }
                }

                return LoginPreloadResponse(captchaRequired = false, clientId = clientId)
            }

            if (loginPageResponse.status != HttpStatusCode.OK) {
                log.error(
                        "Failed to load login page for preload. Status: {}",
                        loginPageResponse.status
                )
                return LoginPreloadResponse(captchaRequired = false, clientId = clientId)
            }

            val loginPageHtml = loginPageResponse.bodyAsText()

            // 获取 execution token
            val execution = CasParser.extractExecution(loginPageHtml)

            // 检测是否需要验证码
            val captchaInfo = CasParser.detectCaptcha(loginPageHtml, CAPTCHA_URL_BASE)

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
                client.get(VpnCipher.toVpnUrl(UC_STATUS_URL)) {
                    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
                    header("X-Requested-With", "XMLHttpRequest")
                    header(
                            HttpHeaders.Referrer,
                            VpnCipher.toVpnUrl("https://uc.buaa.edu.cn/#/user/login")
                    )
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

    companion object {
        private val LOGIN_URL: String = VpnCipher.toVpnUrl("https://sso.buaa.edu.cn/login")
        private val UC_STATUS_URL = "https://uc.buaa.edu.cn/api/uc/status"
        private val CAPTCHA_URL_BASE = VpnCipher.toVpnUrl("https://sso.buaa.edu.cn/captcha")
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

    /** 手动跟随重定向并检查 SSO 登录错误。 */
    private suspend fun followRedirectsAndCheckError(
            initialResponse: HttpResponse,
            noRedirectClient: HttpClient,
            client: HttpClient
    ): HttpResponse {
        var currentResponse = initialResponse
        while (currentResponse.status == HttpStatusCode.Found ||
                currentResponse.status == HttpStatusCode.MovedPermanently ||
                currentResponse.status == HttpStatusCode.SeeOther) {
            val location = currentResponse.headers[HttpHeaders.Location]
            if (location.isNullOrBlank()) break
            log.debug("Following redirect to: {}", location)

            // 使用 java.net.URL 处理相对路径，确保在 JVM 环境下的稳定性
            // 避免 Ktor URLBuilder 在处理某些 WebVPN 格式路径时出现的解析问题
            val nextUrl =
                    try {
                        val base = java.net.URL(currentResponse.request.url.toString())
                        java.net.URL(base, location).toString()
                    } catch (e: Exception) {
                        // 回退逻辑，通常不会触发
                        location
                    }

            currentResponse = noRedirectClient.get(nextUrl)
        }

        val bodyText = runCatching { currentResponse.bodyAsText() }.getOrNull() ?: ""
        val url = currentResponse.request.url.toString()

        // 1. 检查 URL 中的错误信息 (例如 exception.message=...)
        if (url.contains("exception.message=")) {
            val errorMsg = url.substringAfter("exception.message=").decodeURLQueryComponent()
            log.warn("SSO error in URL: {}", errorMsg)
            client.close()
            failLogin(errorMsg)
        }

        // 2. 检查 HTTP 状态码
        if (currentResponse.status == HttpStatusCode.Unauthorized) {
            val tip = CasParser.extractTipText(bodyText)
            client.close()
            failLogin(tip ?: "账号或密码错误")
        }

        // 3. 检查响应体中的错误信息
        val errorMessage = CasParser.findLoginError(bodyText)
        if (errorMessage != null) {
            client.close()
            failLogin(errorMessage)
        }

        // 4. 如果还在登录页，说明登录失败
        if (bodyText.contains("input name=\"execution\"") || bodyText.contains("config.captcha")) {
            client.close()
            failLogin("账号或密码错误")
        }

        return currentResponse
    }
}
