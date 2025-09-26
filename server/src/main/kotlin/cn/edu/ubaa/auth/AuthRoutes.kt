package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.CaptchaRequiredResponse
import cn.edu.ubaa.auth.JwtAuth.getUserSession
import cn.edu.ubaa.auth.JwtAuth.requireUserSession
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

// Define serializable error classes according to the API spec
@kotlinx.serialization.Serializable
data class ErrorResponse(val error: ErrorDetails)

@kotlinx.serialization.Serializable
data class ErrorDetails(val code: String, val message: String)

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
        post("/login") {
            try {
                val request = call.receive<LoginRequest>()
                val loginResponse = authService.loginWithToken(request)
                call.respond(HttpStatusCode.OK, loginResponse)
            } catch (e: ContentTransformationException) {
                call.respond(
                    HttpStatusCode.BadRequest,
                    ErrorResponse(ErrorDetails("invalid_request", "Invalid request body: ${e.message}"))
                )
            } catch (e: CaptchaRequiredException) {
                call.respond(
                    HttpStatusCode.UnprocessableEntity, // 422 - CAPTCHA required
                    CaptchaRequiredResponse(e.captchaInfo, e.message ?: "CAPTCHA verification required")
                )
            } catch (e: LoginException) {
                call.respond(
                    HttpStatusCode.Unauthorized,
                    ErrorResponse(ErrorDetails("invalid_credentials", e.message ?: "Login failed"))
                )
            } catch (e: Exception) {
                // Log the exception for debugging purposes
                application.log.error("An unexpected error occurred during login.", e)
                call.respond(
                    HttpStatusCode.InternalServerError,
                    ErrorResponse(ErrorDetails("internal_server_error", "An unexpected server error occurred."))
                )
            }
        }

        // JWT token validation and session status endpoint
        get("/status") {
            try {
                val session = call.getUserSession()
                if (session != null) {
                    val statusResponse = SessionStatusResponse(
                        user = session.userData,
                        lastActivity = session.lastActivity().toString(),
                        authenticatedAt = session.authenticatedAt.toString()
                    )
                    call.respond(HttpStatusCode.OK, statusResponse)
                } else {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(ErrorDetails("invalid_token", "Invalid or expired JWT token"))
                    )
                }
            } catch (e: Exception) {
                application.log.error("An unexpected error occurred during status check.", e)
                call.respond(
                    HttpStatusCode.InternalServerError,
                    ErrorResponse(ErrorDetails("internal_server_error", "An unexpected server error occurred."))
                )
            }
        }

        // Logout endpoint
        post("/logout") {
            try {
                val session = call.getUserSession()
                if (session != null) {
                    authService.logout(session.username)
                    call.respond(HttpStatusCode.OK, mapOf("message" to "Logged out successfully"))
                } else {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(ErrorDetails("invalid_token", "Invalid or expired JWT token"))
                    )
                }
            } catch (e: Exception) {
                application.log.error("An unexpected error occurred during logout.", e)
                call.respond(
                    HttpStatusCode.InternalServerError,
                    ErrorResponse(ErrorDetails("internal_server_error", "An unexpected server error occurred."))
                )
            }
        }

        // CAPTCHA image endpoint
        get("/captcha/{captchaId}") {
            try {
                val captchaId = call.parameters["captchaId"]
                if (captchaId.isNullOrBlank()) {
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(ErrorDetails("invalid_request", "captchaId parameter is required"))
                    )
                    return@get
                }
                
                // Create a temporary HTTP client for CAPTCHA fetching
                val tempClient = io.ktor.client.HttpClient()
                try {
                    val imageBytes = authService.getCaptchaImage(tempClient, captchaId)
                    if (imageBytes != null) {
                        call.respondBytes(
                            bytes = imageBytes,
                            contentType = ContentType.Image.JPEG
                        )
                    } else {
                        call.respond(
                            HttpStatusCode.NotFound,
                            ErrorResponse(ErrorDetails("captcha_not_found", "CAPTCHA image not found"))
                        )
                    }
                } finally {
                    tempClient.close()
                }
            } catch (e: Exception) {
                application.log.error("An unexpected error occurred during CAPTCHA fetch.", e)
                call.respond(
                    HttpStatusCode.InternalServerError,
                    ErrorResponse(ErrorDetails("internal_server_error", "An unexpected server error occurred."))
                )
            }
        }
    }
}
