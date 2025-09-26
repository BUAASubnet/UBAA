package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.LoginRequest
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
    }
}
