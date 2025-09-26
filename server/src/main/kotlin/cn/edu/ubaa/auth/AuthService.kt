package cn.edu.ubaa.auth

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

        // 2. Post credentials
        client.post(LOGIN_URL) {
            setBody(
                    FormDataContent(
                            Parameters.build {
                                append("username", request.username)
                                append("password", request.password)
                                append("submit", "登录")
                                append("type", "username_password")
                                append("execution", execution)
                                append("_eventId", "submit")
                            }
                    )
            )
        }
        client.get(
                "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
        )
        try {
            val userData = verifySession(client)
            if (userData != null) {
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

    suspend fun login(request: LoginRequest): UserData {
        log.info("Starting login process for user: {}", request.username)

        sessionManager.getSession(request.username)?.let { existingSession ->
            log.debug("Validating cached session for user: {}", request.username)
            val cachedUser = runCatching { verifySession(existingSession.client) }.getOrNull()
            if (cachedUser != null) {
                log.info("Reusing cached session for user: {}", request.username)
                return cachedUser
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

        // 2. Post credentials
        client.post(LOGIN_URL) {
            setBody(
                    FormDataContent(
                            Parameters.build {
                                append("username", request.username)
                                append("password", request.password)
                                append("submit", "登录")
                                append("type", "username_password")
                                append("execution", execution)
                                append("_eventId", "submit")
                            }
                    )
            )
        }
        client.get(
                "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
        )
        try {
            val userData = verifySession(client)
            if (userData != null) {
                sessionManager.commitSession(sessionCandidate, userData)
                log.info("Session verified successfully for user: {}.", request.username)
                return userData
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

    companion object {
        private const val VPN_SERVICE_URL = "https://d.buaa.edu.cn/login?cas_login=true"
        private val LOGIN_URL: String =
                "https://sso.buaa.edu.cn/login?service=" +
                        URLEncoder.encode(VPN_SERVICE_URL, StandardCharsets.UTF_8.name())
        private const val UC_STATUS_URL = "https://uc.buaa.edu.cn/api/uc/status"
    }
}

class LoginException(message: String) : Exception(message)
