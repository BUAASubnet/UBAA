package cn.edu.ubaa.user

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.authenticatedRoute
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

fun Route.userRouting() {
    val userService = UserService()

    route("/api/v1/user") {
        authenticatedRoute {
            get("/info") {
                val username = call.jwtUsername
                if (username.isNullOrBlank()) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(ErrorDetails("invalid_token", "Invalid or expired JWT token"))
                    )
                    return@get
                }

                try {
                    val userInfo = userService.fetchUserInfo(username)
                    call.respond(HttpStatusCode.OK, userInfo)
                } catch (e: LoginException) {
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(ErrorDetails("unauthenticated", e.message ?: "Session is not available."))
                    )
                } catch (e: UserInfoException) {
                    call.respond(
                        HttpStatusCode.BadGateway,
                        ErrorResponse(ErrorDetails("upstream_error", e.message ?: "Failed to fetch user info."))
                    )
                } catch (e: Exception) {
                    call.application.environment.log.error("Unexpected error while fetching user info.", e)
                    call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(ErrorDetails("internal_server_error", "An unexpected server error occurred."))
                    )
                }
            }
        }
    }
}
