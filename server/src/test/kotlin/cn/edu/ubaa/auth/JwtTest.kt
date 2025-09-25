package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.UserData
import java.time.Duration
import kotlin.test.*

class JwtUtilTest {

    @Test
    fun testJwtGenerationAndValidation() {
        val username = "testuser"
        val ttl = Duration.ofMinutes(30)

        // Generate token
        val token = JwtUtil.generateToken(username, ttl)
        assertNotNull(token)
        assertTrue(token.isNotBlank())

        // Validate token
        val extractedUsername = JwtUtil.validateTokenAndGetUsername(token)
        assertEquals(username, extractedUsername)
    }

    @Test
    fun testJwtExpiration() {
        val username = "testuser"
        val shortTtl = Duration.ofMillis(1) // Very short TTL

        val token = JwtUtil.generateToken(username, shortTtl)
        
        // Wait for token to expire
        Thread.sleep(10)
        
        val extractedUsername = JwtUtil.validateTokenAndGetUsername(token)
        assertNull(extractedUsername) // Should be null due to expiration
        
        assertTrue(JwtUtil.isTokenExpired(token))
    }

    @Test
    fun testInvalidToken() {
        val invalidToken = "invalid.jwt.token"
        val extractedUsername = JwtUtil.validateTokenAndGetUsername(invalidToken)
        assertNull(extractedUsername)
        
        assertTrue(JwtUtil.isTokenExpired(invalidToken))
    }

    @Test
    fun testExtractUsernameWithoutValidation() {
        val username = "testuser"
        val ttl = Duration.ofMinutes(30)
        
        val token = JwtUtil.generateToken(username, ttl)
        val extractedUsername = JwtUtil.extractUsernameWithoutValidation(token)
        assertEquals(username, extractedUsername)
        
        // Should work even with expired token
        val expiredToken = JwtUtil.generateToken(username, Duration.ofMillis(1))
        Thread.sleep(10)
        val extractedFromExpired = JwtUtil.extractUsernameWithoutValidation(expiredToken)
        assertEquals(username, extractedFromExpired)
    }
}

class SessionManagerJwtTest {

    @Test
    fun testSessionWithTokenCommit() {
        val sessionManager = SessionManager()
        val username = "testuser"
        val userData = UserData("Test User", "123456")

        val candidate = sessionManager.prepareSession(username)
        val sessionWithToken = sessionManager.commitSessionWithToken(candidate, userData)

        assertNotNull(sessionWithToken.jwtToken)
        assertEquals(userData, sessionWithToken.session.userData)
        assertEquals(username, sessionWithToken.session.username)

        // Verify token maps to session
        val retrievedSession = sessionManager.getSessionByToken(sessionWithToken.jwtToken)
        assertNotNull(retrievedSession)
        assertEquals(username, retrievedSession.username)
    }

    @Test
    fun testGetSessionByInvalidToken() {
        val sessionManager = SessionManager()
        val session = sessionManager.getSessionByToken("invalid.token")
        assertNull(session)
    }

    @Test
    fun testInvalidateSessionByToken() {
        val sessionManager = SessionManager()
        val username = "testuser"
        val userData = UserData("Test User", "123456")

        val candidate = sessionManager.prepareSession(username)
        val sessionWithToken = sessionManager.commitSessionWithToken(candidate, userData)

        // Verify session exists
        val retrievedSession = sessionManager.getSessionByToken(sessionWithToken.jwtToken)
        assertNotNull(retrievedSession)

        // Invalidate by token
        sessionManager.invalidateSessionByToken(sessionWithToken.jwtToken)

        // Verify session is gone
        val sessionAfterInvalidation = sessionManager.getSessionByToken(sessionWithToken.jwtToken)
        assertNull(sessionAfterInvalidation)
    }

    @Test
    fun testCleanupExpiredTokens() {
        val sessionManager = SessionManager(Duration.ofMillis(50)) // Very short TTL
        val username = "testuser"
        val userData = UserData("Test User", "123456")

        val candidate = sessionManager.prepareSession(username)
        val sessionWithToken = sessionManager.commitSessionWithToken(candidate, userData)

        // Verify session exists
        val retrievedSession = sessionManager.getSessionByToken(sessionWithToken.jwtToken)
        assertNotNull(retrievedSession)

        // Wait for session to expire
        Thread.sleep(100)

        // Clean up expired sessions
        sessionManager.cleanupExpiredSessions()

        // Verify session is cleaned up
        val sessionAfterCleanup = sessionManager.getSessionByToken(sessionWithToken.jwtToken)
        assertNull(sessionAfterCleanup)
    }
}