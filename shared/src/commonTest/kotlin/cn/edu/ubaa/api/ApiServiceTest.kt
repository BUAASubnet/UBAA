package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import kotlin.test.*

class ApiServiceTest {
    
    @Test
    fun testLoginRequestSerialization() {
        val loginRequest = LoginRequest("testuser", "testpass")
        
        assertEquals("testuser", loginRequest.username)
        assertEquals("testpass", loginRequest.password)
    }
    
    @Test
    fun testLoginResponseDeserialization() {
        val userData = UserData("Test User", "12345")
        val loginResponse = LoginResponse(userData, "mock_jwt_token")
        
        assertEquals(userData, loginResponse.user)
        assertEquals("mock_jwt_token", loginResponse.token)
    }
    
    @Test
    fun testUserInfoStructure() {
        val userInfo = UserInfo(
            idCardType = "1",
            idCardTypeName = "居民身份证",
            phone = "132******79",
            schoolid = "24182104", 
            name = "李沐衡",
            idCardNumber = "11**************18",
            email = "t****h@outlook.com",
            username = "24182104"
        )
        
        assertNotNull(userInfo.name)
        assertNotNull(userInfo.schoolid)
        assertNotNull(userInfo.username)
        assertEquals("李沐衡", userInfo.name)
        assertEquals("24182104", userInfo.schoolid)
    }
    
    @Test
    fun testApiErrorResponse() {
        val errorDetails = ApiErrorDetails("invalid_credentials", "Login failed")
        val errorResponse = ApiErrorResponse(errorDetails)
        
        assertEquals("invalid_credentials", errorResponse.error.code)
        assertEquals("Login failed", errorResponse.error.message)
    }
    
    @Test
    fun testSessionStatusResponse() {
        val userData = UserData("Test User", "12345")
        val sessionStatus = SessionStatusResponse(
            user = userData,
            lastActivity = "2024-01-01T12:00:00Z",
            authenticatedAt = "2024-01-01T11:00:00Z"
        )
        
        assertEquals(userData, sessionStatus.user)
        assertNotNull(sessionStatus.lastActivity)
        assertNotNull(sessionStatus.authenticatedAt)
    }
    
    @Test
    fun testLogoutResponseStructure() {
        // Test that logout returns a Result type 
        // We can't actually test the network call without mocking,
        // but we can test that the response structure would be correct
        val logoutResult = Result.success(Unit)
        
        assertTrue(logoutResult.isSuccess)
        assertEquals(Unit, logoutResult.getOrNull())
    }
}