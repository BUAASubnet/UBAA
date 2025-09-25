package cn.edu.ubaa.auth

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.auth.jwt.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import kotlinx.serialization.Serializable

@Serializable
data class JwtErrorResponse(val error: JwtErrorDetails)

@Serializable
data class JwtErrorDetails(val code: String, val message: String)

/**
 * JWT Authentication configuration and utilities for protecting routes.
 */
object JwtAuth {
    const val JWT_AUTH = "jwt-auth"
    
    // Use the same secret as JwtUtil
    private val jwtSecret = System.getenv("JWT_SECRET") ?: "ubaa-default-jwt-secret-change-in-production"
    private val algorithm = Algorithm.HMAC256(jwtSecret)
    private const val issuer = "ubaa-server"
    private const val audienceClaim = "ubaa-users"
    
    /**
     * Configures JWT authentication for the Ktor application.
     */
    fun Application.configureJwtAuth() {
        install(Authentication) {
            jwt(JWT_AUTH) {
                verifier(
                    JWT.require(algorithm)
                        .withIssuer(issuer)
                        .withAudience(audienceClaim)
                        .build()
                )
                validate { credential ->
                    val username = credential.payload.subject
                    if (username != null && 
                        GlobalSessionManager.instance.getSession(username) != null) {
                        JWTPrincipal(credential.payload)
                    } else {
                        null
                    }
                }
                challenge { _, _ ->
                    call.respond(
                        HttpStatusCode.Unauthorized,
                        JwtErrorResponse(JwtErrorDetails("invalid_token", "Invalid or expired JWT token"))
                    )
                }
            }
        }
    }
    
    /**
     * Extension function to get the username from JWT principal.
     */
    val ApplicationCall.jwtUsername: String?
        get() = principal<JWTPrincipal>()?.payload?.subject
        
    /**
     * Extension function to get the user session from JWT token in the request.
     */
    suspend fun ApplicationCall.getUserSession(): SessionManager.UserSession? {
        val authHeader = request.headers[HttpHeaders.Authorization]
        if (authHeader?.startsWith("Bearer ") == true) {
            val token = authHeader.removePrefix("Bearer ")
            return GlobalSessionManager.instance.getSessionByToken(token)
        }
        return null
    }
    
    /**
     * Extension function to require a user session, throwing an exception if not found.
     */
    suspend fun ApplicationCall.requireUserSession(): SessionManager.UserSession {
        return getUserSession() 
            ?: throw IllegalStateException("No valid session found for JWT token")
    }
}

/**
 * Route extension to apply JWT authentication.
 */
fun Route.authenticatedRoute(build: Route.() -> Unit): Route {
    return authenticate(JwtAuth.JWT_AUTH) {
        build()
    }
}