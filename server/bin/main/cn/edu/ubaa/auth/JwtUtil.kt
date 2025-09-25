package cn.edu.ubaa.auth

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.auth0.jwt.exceptions.JWTVerificationException
import java.time.Duration
import java.time.Instant
import java.util.*

/**
 * JWT utility class for generating, validating, and parsing JWT tokens.
 * Each JWT token corresponds to a user session in the SessionManager.
 */
object JwtUtil {
    
    // In production, this should be loaded from environment variables or configuration
    private val jwtSecret = System.getenv("JWT_SECRET") ?: "ubaa-default-jwt-secret-change-in-production"
    private val algorithm = Algorithm.HMAC256(jwtSecret)
    private const val issuer = "ubaa-server"
    private const val audienceClaim = "ubaa-users"
    
    /**
     * Generates a JWT token for the given username with session TTL expiration.
     * 
     * @param username The username to include in the token
     * @param sessionTtl The session time-to-live duration
     * @return The signed JWT token string
     */
    fun generateToken(username: String, sessionTtl: Duration): String {
        val now = Instant.now()
        val expiration = Date.from(now.plus(sessionTtl))
        
        return JWT.create()
            .withIssuer(issuer)
            .withAudience(audienceClaim)
            .withSubject(username)
            .withIssuedAt(Date.from(now))
            .withExpiresAt(expiration)
            .withClaim("username", username)
            .sign(algorithm)
    }
    
    /**
     * Validates a JWT token and extracts the username if valid.
     * 
     * @param token The JWT token to validate
     * @return The username if the token is valid, null otherwise
     */
    fun validateTokenAndGetUsername(token: String): String? {
        return try {
            val verifier = JWT.require(algorithm)
                .withIssuer(issuer)
                .withAudience(audienceClaim)
                .build()
                
            val decodedJWT = verifier.verify(token)
            decodedJWT.subject
        } catch (e: JWTVerificationException) {
            null
        }
    }
    
    /**
     * Extracts username from token without validation (for logging/debugging).
     * 
     * @param token The JWT token to decode
     * @return The username if the token can be decoded, null otherwise
     */
    fun extractUsernameWithoutValidation(token: String): String? {
        return try {
            val decodedJWT = JWT.decode(token)
            decodedJWT.subject
        } catch (e: Exception) {
            null
        }
    }
    
    /**
     * Checks if a token is expired without full validation.
     * 
     * @param token The JWT token to check
     * @return True if the token is expired, false otherwise or if token is invalid
     */
    fun isTokenExpired(token: String): Boolean {
        return try {
            val decodedJWT = JWT.decode(token)
            val expiration = decodedJWT.expiresAt
            expiration?.before(Date()) ?: true
        } catch (e: Exception) {
            true
        }
    }
}