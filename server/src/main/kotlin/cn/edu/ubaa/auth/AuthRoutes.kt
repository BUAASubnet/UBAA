package cn.edu.ubaa.auth

import cn.edu.ubaa.auth.JwtAuth.getUserSession
import cn.edu.ubaa.model.dto.CaptchaRequiredResponse
import cn.edu.ubaa.model.dto.LoginRequest
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

// 错误响应类，前后端统一
@kotlinx.serialization.Serializable data class ErrorResponse(val error: ErrorDetails)

@kotlinx.serialization.Serializable data class ErrorDetails(val code: String, val message: String)

@kotlinx.serialization.Serializable
data class SessionStatusResponse(
        val user: cn.edu.ubaa.model.dto.UserData,
        val lastActivity: String,
        val authenticatedAt: String
)

fun Route.authRouting() {
        val sessionManager = GlobalSessionManager.instance
        val authService = AuthService(sessionManager)

        route("/api/v1/auth") {
                // 预加载登录状态：为 clientId 创建专属会话，获取验证码（如果需要）
                post("/preload") {
                        try {
                                val request =
                                        call.receive<cn.edu.ubaa.model.dto.LoginPreloadRequest>()
                                application.log.info(
                                        "Preloading login state for clientId: {}",
                                        request.clientId
                                )
                                val preloadResponse =
                                        authService.preloadLoginState(request.clientId)
                                call.respond(HttpStatusCode.OK, preloadResponse)
                        } catch (e: ContentTransformationException) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "Invalid request body: clientId is required"
                                                )
                                        )
                                )
                        } catch (e: Exception) {
                                application.log.error(
                                        "An unexpected error occurred during login preload.",
                                        e
                                )
                                call.respond(
                                        HttpStatusCode.InternalServerError,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "internal_server_error",
                                                        "Failed to preload login state"
                                                )
                                        )
                                )
                        }
                }

                // 登录接口
                post("/login") {
                        try {
                                val request = call.receive<LoginRequest>()
                                application.log.info("Login attempt for user: {}", request.username)
                                val loginResponse = authService.loginWithToken(request)
                                application.log.info(
                                        "Login successful for user: {}",
                                        request.username
                                )
                                call.respond(HttpStatusCode.OK, loginResponse)
                        } catch (e: ContentTransformationException) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "Invalid request body: ${e.message}"
                                                )
                                        )
                                )
                        } catch (e: CaptchaRequiredException) {
                                call.respond(
                                        HttpStatusCode.UnprocessableEntity, // 需验证码
                                        CaptchaRequiredResponse(
                                                e.captchaInfo,
                                                e.execution,
                                                e.message ?: "需要验证码"
                                        )
                                )
                        } catch (e: LoginException) {
                                call.respond(
                                        HttpStatusCode.Unauthorized,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_credentials",
                                                        e.message ?: "Login failed"
                                                )
                                        )
                                )
                        } catch (e: Exception) {
                                // 记录异常，便于排查
                                application.log.error(
                                        "An unexpected error occurred during login.",
                                        e
                                )
                                call.respond(
                                        HttpStatusCode.InternalServerError,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "internal_server_error",
                                                        "An unexpected server error occurred."
                                                )
                                        )
                                )
                        }
                }

                // 查询会话状态，校验 JWT
                get("/status") {
                        try {
                                val session = call.getUserSession()
                                if (session != null) {
                                        application.log.info(
                                                "Session status check: user {} is authenticated",
                                                session.userData.name
                                        )
                                        val statusResponse =
                                                SessionStatusResponse(
                                                        user = session.userData,
                                                        lastActivity =
                                                                session.lastActivity().toString(),
                                                        authenticatedAt =
                                                                session.authenticatedAt.toString()
                                                )
                                        call.respond(HttpStatusCode.OK, statusResponse)
                                } else {
                                        application.log.warn(
                                                "Session status check failed: invalid or expired token"
                                        )
                                        call.respond(
                                                HttpStatusCode.Unauthorized,
                                                ErrorResponse(
                                                        ErrorDetails(
                                                                "invalid_token",
                                                                "Invalid or expired JWT token"
                                                        )
                                                )
                                        )
                                }
                        } catch (e: Exception) {
                                application.log.error(
                                        "An unexpected error occurred during status check.",
                                        e
                                )
                                call.respond(
                                        HttpStatusCode.InternalServerError,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "internal_server_error",
                                                        "An unexpected server error occurred."
                                                )
                                        )
                                )
                        }
                }

                // 注销，清理会话
                post("/logout") {
                        try {
                                val session = call.getUserSession()
                                if (session != null) {
                                        authService.logout(session.username)
                                        call.respond(
                                                HttpStatusCode.OK,
                                                mapOf("message" to "Logged out successfully")
                                        )
                                } else {
                                        call.respond(
                                                HttpStatusCode.Unauthorized,
                                                ErrorResponse(
                                                        ErrorDetails(
                                                                "invalid_token",
                                                                "Invalid or expired JWT token"
                                                        )
                                                )
                                        )
                                }
                        } catch (e: Exception) {
                                application.log.error(
                                        "An unexpected error occurred during logout.",
                                        e
                                )
                                call.respond(
                                        HttpStatusCode.InternalServerError,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "internal_server_error",
                                                        "An unexpected server error occurred."
                                                )
                                        )
                                )
                        }
                }

                // 获取验证码图片
                get("/captcha/{captchaId}") {
                        try {
                                val captchaId = call.parameters["captchaId"]
                                if (captchaId.isNullOrBlank()) {
                                        call.respond(
                                                HttpStatusCode.BadRequest,
                                                ErrorResponse(
                                                        ErrorDetails(
                                                                "invalid_request",
                                                                "captchaId parameter is required"
                                                        )
                                                )
                                        )
                                        return@get
                                }

                                // 复用 Client，减少资源消耗
                                val imageBytes =
                                        authService.getCaptchaImage(
                                                cn.edu.ubaa.utils.HttpClients.sharedClient,
                                                captchaId
                                        )
                                if (imageBytes != null) {
                                        call.respondBytes(
                                                bytes = imageBytes,
                                                contentType = ContentType.Image.JPEG
                                        )
                                } else {
                                        call.respond(
                                                HttpStatusCode.NotFound,
                                                ErrorResponse(
                                                        ErrorDetails(
                                                                "captcha_not_found",
                                                                "CAPTCHA image not found"
                                                        )
                                                )
                                        )
                                }
                        } catch (e: Exception) {
                                application.log.error(
                                        "An unexpected error occurred during CAPTCHA fetch.",
                                        e
                                )
                                call.respond(
                                        HttpStatusCode.InternalServerError,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "internal_server_error",
                                                        "An unexpected server error occurred."
                                                )
                                        )
                                )
                        }
                }
        }
}
