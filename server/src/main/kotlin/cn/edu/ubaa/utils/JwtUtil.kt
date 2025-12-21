package cn.edu.ubaa.utils

import com.auth0.jwt.JWT
import com.auth0.jwt.algorithms.Algorithm
import com.auth0.jwt.exceptions.JWTVerificationException
import java.time.Duration
import java.time.Instant
import java.util.Date

/**
 * JWT 工具类
 * 用于生成、验证和解析对应用户会话的 JWT Token。
 */
object JwtUtil {

    // 强制要求显式配置密钥，避免在生产环境使用不安全的默认值
    private val jwtSecret: String =
            System.getenv("JWT_SECRET")
                    ?: System.getProperty("JWT_SECRET")
                            ?: run {
                        System.err.println(
                                "ERROR: JWT_SECRET is not set! Using insecure default for development only."
                        )
                        "ubaa-dev-secret-do-not-use-in-production"
                    }
    
    val algorithm: Algorithm = Algorithm.HMAC256(jwtSecret)
    const val ISSUER = "ubaa-server"
    const val AUDIENCE = "ubaa-users"

    /**
     * 生成包含用户名的 JWT Token，并设置过期时间。
     */
    fun generateToken(username: String, sessionTtl: Duration): String {
        val now = Instant.now()
        val expiration = Date.from(now.plus(sessionTtl))

        return JWT.create()
                .withIssuer(ISSUER)
                .withAudience(AUDIENCE)
                .withSubject(username)
                .withIssuedAt(Date.from(now))
                .withExpiresAt(expiration)
                .withClaim("username", username)
                .sign(algorithm)
    }

    /**
     * 验证 Token 有效性并提取用户名。
     */
    fun validateTokenAndGetUsername(token: String): String? {
        return try {
            val verifier =
                    JWT.require(algorithm).withIssuer(ISSUER).withAudience(AUDIENCE).build()

            val decodedJWT = verifier.verify(token)
            decodedJWT.subject
        } catch (e: JWTVerificationException) {
            null
        }
    }

    /**
     * 无需验证即可从 Token 中解码用户名（仅用于日志或调试）。
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
     * 检查 Token 是否过期（不进行完整签名验证）。
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
