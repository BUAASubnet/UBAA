package cn.edu.ubaa.auth

import cn.edu.ubaa.utils.JwtUtil
import com.auth0.jwt.JWT
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.auth.jwt.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.util.AttributeKey
import kotlinx.serialization.Serializable

@Serializable data class JwtErrorResponse(val error: JwtErrorDetails)

@Serializable data class JwtErrorDetails(val code: String, val message: String)

/** JWT Authentication configuration and utilities for protecting routes. */
object JwtAuth {
  const val JWT_AUTH = "jwt-auth"
  private val sessionAttributeKey = AttributeKey<SessionManager.UserSession>("user-session")

  /** Configures JWT authentication for the Ktor application. */
  fun Application.configureJwtAuth() {
    install(Authentication) {
      jwt(JWT_AUTH) {
        verifier(
            JWT.require(JwtUtil.algorithm)
                .withIssuer(JwtUtil.ISSUER)
                .withAudience(JwtUtil.AUDIENCE)
                .build()
        )
        validate { credential ->
          val username = credential.payload.subject
          if (
              username != null &&
                  GlobalSessionManager.instance.getSession(
                      username,
                      SessionManager.SessionAccess.READ_ONLY,
                  ) != null
          ) {
            JWTPrincipal(credential.payload)
          } else {
            null
          }
        }
        challenge { _, _ ->
          call.respond(
              HttpStatusCode.Unauthorized,
              JwtErrorResponse(JwtErrorDetails("invalid_token", "登录状态已失效，请重新登录")),
          )
        }
      }
    }
  }

  /** Extension function to get the username from JWT principal. */
  val ApplicationCall.jwtUsername: String?
    get() = principal<JWTPrincipal>()?.payload?.subject

  suspend fun ApplicationCall.currentUserSession(
      sessionManager: SessionManager = GlobalSessionManager.instance
  ): SessionManager.UserSession? {
    attributes.getOrNull(sessionAttributeKey)?.let {
      return it
    }

    val session =
        when (val username = jwtUsername) {
          null -> {
            val authHeader = request.headers[HttpHeaders.Authorization]
            if (authHeader?.startsWith("Bearer ") != true) return null
            val token = authHeader.removePrefix("Bearer ")
            sessionManager.getSessionByToken(token, SessionManager.SessionAccess.TOUCH)
          }
          else -> sessionManager.getSession(username, SessionManager.SessionAccess.TOUCH)
        } ?: return null

    attributes.put(sessionAttributeKey, session)
    return session
  }

  /** Extension function to get the user session from the authenticated request. */
  suspend fun ApplicationCall.getUserSession(
      sessionManager: SessionManager = GlobalSessionManager.instance
  ): SessionManager.UserSession? {
    return currentUserSession(sessionManager)
  }

  /** Extension function to require a user session, throwing an exception if not found. */
  suspend fun ApplicationCall.requireUserSession(
      sessionManager: SessionManager = GlobalSessionManager.instance
  ): SessionManager.UserSession {
    return currentUserSession(sessionManager)
        ?: throw IllegalStateException("No valid session found for request")
  }
}

/** Route extension to apply JWT authentication. */
fun Route.authenticatedRoute(build: Route.() -> Unit): Route {
  return authenticate(JwtAuth.JWT_AUTH) { build() }
}
