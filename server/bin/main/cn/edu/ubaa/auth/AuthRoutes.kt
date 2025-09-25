package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.LoginRequest
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

// Define serializable error classes according to the API spec
@kotlinx.serialization.Serializable
data class ErrorResponse(val error: ErrorDetails)

@kotlinx.serialization.Serializable
data class ErrorDetails(val code: String, val message: String)

fun Route.authRouting() {
    val sessionManager = GlobalSessionManager.instance
    val authService = AuthService(sessionManager)

    route("/api/v1/auth") {
        post("/login") {
            try {
                val request = call.receive<LoginRequest>()
                val userData = authService.login(request)
                call.respond(HttpStatusCode.OK, userData)
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
    }
}
