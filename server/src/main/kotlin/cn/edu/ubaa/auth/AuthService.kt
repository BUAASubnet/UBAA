package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.LoginResponse
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfoResponse
import cn.edu.ubaa.utils.JwtUtil
import io.ktor.client.HttpClient
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.time.Duration
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.jsoup.Jsoup
import org.slf4j.LoggerFactory

class AuthService(private val sessionManager: SessionManager = GlobalSessionManager.instance) {

    private val log = LoggerFactory.getLogger(AuthService::class.java)

    /** Performs login and returns both user data and JWT token. */
    suspend fun loginWithToken(request: LoginRequest): LoginResponse {
        log.info("Starting login process with JWT for user: {}", request.username)

        sessionManager.getSession(request.username)?.let { existingSession ->
            log.debug("Validating cached session for user: {}", request.username)
            val cachedUser = runCatching { verifySession(existingSession.client) }.getOrNull()
            if (cachedUser != null) {
                log.info("Reusing cached session for user: {}", request.username)
                // Generate a new JWT for the existing session
                val newToken = JwtUtil.generateToken(request.username, Duration.ofMinutes(30))
                return LoginResponse(cachedUser, newToken)
            }
            log.info("Cached session for user {} is invalid. Re-authenticating.", request.username)
            sessionManager.invalidateSession(request.username)
        }

        val sessionCandidate = sessionManager.prepareSession(request.username)
        val client = sessionCandidate.client

        // 1. Get execution token
        val loginPageResponse = client.get(LOGIN_URL)
        if (loginPageResponse.status != HttpStatusCode.OK) {
            log.error("Failed to load login page. Status: {}", loginPageResponse.status)
            client.close()
            throw LoginException("Failed to load login page. Status: ${loginPageResponse.status}")
        }
        val loginPageHtml = loginPageResponse.bodyAsText()
        val doc = Jsoup.parse(loginPageHtml)
        val execution = doc.select("input[name=execution]").`val`()
        log.debug("Got execution token: {}...", execution.take(10))

        if (execution.isNullOrBlank()) {
            log.warn("Could not find execution token on login page.")
            throw LoginException("Could not find execution token on login page.")
        }

        // Check for CAPTCHA requirement in loginWithToken method
        val captchaInfo = detectCaptcha(loginPageHtml)
        if (captchaInfo != null && request.captcha.isNullOrBlank()) {
            log.info("CAPTCHA required for user: {}", request.username)
            client.close()
            throw CaptchaRequiredException(captchaInfo)
        }

        // 2. Post credentials
        val loginSubmitResponse =
                client.post(LOGIN_URL) {
                    setBody(
                            FormDataContent(
                                    Parameters.build {
                                        append("username", request.username)
                                        append("password", request.password)
                                        request.captcha?.let { append("captcha", it) }
                                        append("submit", "登录")
                                        append("type", "username_password")
                                        append("execution", execution)
                                        append("_eventId", "submit")
                                    }
                            )
                    )
                }

        log.debug("Login form submitted. Response status: {}", loginSubmitResponse.status)
        log.debug("response content: {}", loginSubmitResponse.bodyAsText())

        findLoginError(loginSubmitResponse)?.let { errorMessage ->
            client.close()
            throw LoginException("Login failed: $errorMessage")
        }

        client.get(
                "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
        )
        try {
            val userData = verifySession(client)
            if (userData != null) {
                // Initialize BYXT session for schedule access
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
            val errorDoc = Jsoup.parse(loginPageHtml)
            val errorTip = errorDoc.select(".tip-text").text()
            if (errorTip.isNotBlank()) {
                client.close()
                throw LoginException("Login failed: $errorTip")
            }
            client.close()
            throw LoginException("Session verification failed after login.")
        } catch (e: LoginException) {
            throw e
        } catch (e: Exception) {
            client.close()
            log.error("Error while verifying session for user: {}", request.username, e)
            throw LoginException("An error occurred during session verification.")
        }
    }

    /** Performs logout by calling BUAA SSO logout and invalidating the session. */
    suspend fun logout(username: String) {
        log.info("Starting logout process for user: {}", username)

        val session = sessionManager.getSession(username)
        if (session != null) {
            try {
                // Call BUAA SSO logout endpoint to properly terminate the SSO session
                val logoutResponse = session.client.get("https://sso.buaa.edu.cn/logout")
                log.debug("SSO logout response status: {}", logoutResponse.status)
            } catch (e: Exception) {
                log.warn("Error calling BUAA SSO logout for user: {}", username, e)
                // Continue with session invalidation even if SSO logout fails
            }

            // Invalidate the session in our system
            sessionManager.invalidateSession(username)
            log.info("Session invalidated successfully for user: {}", username)
        } else {
            log.warn("No active session found for user: {}", username)
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
        log.debug("Status API response body: {}", statusBody)

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
                null
            }
        } catch (e: Exception) {
            log.error("Failed to parse user info from status API response.", e)
            null
        }
    }

    /**
     * Initializes BYXT (博雅校园通) session by performing SSO authentication.
     *
     * The correct flow is:
     * 1. Access BYXT index.do → redirects to SSO with service parameter
     * 2. SSO (already logged in) → redirects back with ticket parameter
     * 3. BYXT validates ticket → sets GS_SESSIONID cookie
     * 4. Session is now authenticated for BYXT APIs
     */
    private suspend fun initializeByxtSession(client: HttpClient) {
        log.debug("Initializing BYXT session via SSO")
        try {
            // The key is to access the index.do endpoint which will trigger the SSO flow
            // Since followRedirects=true, Ktor will automatically follow all redirects
            // including the SSO redirect with the ticket
            val byxtIndexUrl = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do"

            log.debug("Step 1: Accessing BYXT index.do to trigger SSO authentication")
            val byxtResponse = client.get(byxtIndexUrl)
            log.debug("BYXT index.do response status: {}", byxtResponse.status)

            // If we get 200 OK, the SSO authentication was successful
            if (byxtResponse.status == HttpStatusCode.OK) {
                val body = byxtResponse.bodyAsText()
                // Check if we got the actual page content (not a login page)
                if (body.contains("homeapp") || body.contains("首页") || body.length > 1000) {
                    log.info("BYXT session initialized successfully via SSO redirect flow")

                    // Optionally verify by calling an API endpoint
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
            // Don't throw - BYXT initialization failure shouldn't block login
        }
    }

    companion object {
        // 使用直连地址而非 WebVPN
        private const val UC_SERVICE_URL = "https://uc.buaa.edu.cn/"
        private val LOGIN_URL: String =
                "https://sso.buaa.edu.cn/login?service=" +
                        URLEncoder.encode(UC_SERVICE_URL, StandardCharsets.UTF_8.name())
        private const val UC_STATUS_URL = "https://uc.buaa.edu.cn/api/uc/status"
        private const val CAPTCHA_URL_BASE = "https://sso.buaa.edu.cn/captcha"

        // BYXT (博雅校园通) 需要通过 SSO 认证
        private const val BYXT_SERVICE_URL = "https://byxt.buaa.edu.cn/"
        private val BYXT_SSO_URL: String =
                "https://sso.buaa.edu.cn/login?service=" +
                        URLEncoder.encode(BYXT_SERVICE_URL, StandardCharsets.UTF_8.name())
    }

    private suspend fun findLoginError(response: HttpResponse): String? {
        if (response.status == HttpStatusCode.OK) return null

        val responseBody = runCatching { response.bodyAsText() }.getOrNull() ?: return null
        if (responseBody.isBlank()) return null

        return try {
            val doc = Jsoup.parse(responseBody)
            val errorText = doc.select("div.alert.alert-danger#errorDiv p").text()

            if (errorText.isNotBlank()) errorText else null
        } catch (e: Exception) {
            log.debug("Failed to parse login error message from CAS response.", e)
            null
        }
    }

    /**
     * Detects CAPTCHA configuration from login page HTML. Returns CaptchaInfo if CAPTCHA is
     * detected, null otherwise.
     */
    private fun detectCaptcha(loginPageHtml: String): CaptchaInfo? {
        try {
            // Look for JavaScript config pattern: config.captcha = { type: 'image', id:
            // '8211701280' };
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

    /** Fetches CAPTCHA image as byte array. */
    suspend fun getCaptchaImage(client: HttpClient, captchaId: String): ByteArray? {
        return try {
            log.debug("Fetching CAPTCHA image for id: {}", captchaId)
            val response = client.get("$CAPTCHA_URL_BASE?captchaId=$captchaId")
            if (response.status == HttpStatusCode.OK) {
                response.readBytes()
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
        message: String = "CAPTCHA verification required"
) : Exception(message)
