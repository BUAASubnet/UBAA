package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*

/**
 * Authentication service for handling login/logout operations
 */
class AuthService(private val apiClient: ApiClient = ApiClient()) {
    
    suspend fun login(username: String, password: String): Result<LoginResponse> {
        return try {
            val response = apiClient.getClient().post("api/v1/auth/login") {
                contentType(ContentType.Application.Json)
                setBody(LoginRequest(username, password))
            }
            
            when (response.status) {
                HttpStatusCode.OK -> {
                    val loginResponse = response.body<LoginResponse>()
                    // Update the client with the new token
                    apiClient.updateToken(loginResponse.token)
                    Result.success(loginResponse)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(Exception("Login failed with status: ${response.status}"))
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    suspend fun getAuthStatus(): Result<SessionStatusResponse> {
        return try {
            val response = apiClient.getClient().get("api/v1/auth/status")
            
            when (response.status) {
                HttpStatusCode.OK -> {
                    val status = response.body<SessionStatusResponse>()
                    Result.success(status)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(Exception("Status check failed with status: ${response.status}"))
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
    
    suspend fun logout(): Result<Unit> {
        return try {
            val response = apiClient.getClient().post("api/v1/auth/logout")
            
            when (response.status) {
                HttpStatusCode.OK -> {
                    // Close the API client after successful logout
                    apiClient.close()
                    Result.success(Unit)
                }
                HttpStatusCode.Unauthorized -> {
                    // Even if unauthorized, clear local state
                    apiClient.close()
                    Result.success(Unit)
                }
                else -> {
                    // Even if server logout fails, clear local state
                    apiClient.close()
                    Result.failure(Exception("Logout failed with status: ${response.status}"))
                }
            }
        } catch (e: Exception) {
            // Even if network request fails, clear local state
            apiClient.close()
            Result.failure(e)
        }
    }
}

/**
 * User service for fetching user information
 */
class UserService(private val apiClient: ApiClient = ApiClient()) {
    
    suspend fun getUserInfo(): Result<UserInfo> {
        return try {
            val response = apiClient.getClient().get("api/v1/user/info")
            
            when (response.status) {
                HttpStatusCode.OK -> {
                    val userInfo = response.body<UserInfo>()
                    Result.success(userInfo)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(Exception("Failed to fetch user info with status: ${response.status}"))
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

// Additional DTOs needed for API responses
@kotlinx.serialization.Serializable
data class ApiErrorResponse(val error: ApiErrorDetails)

@kotlinx.serialization.Serializable
data class ApiErrorDetails(val code: String, val message: String)

@kotlinx.serialization.Serializable
data class SessionStatusResponse(
    val user: UserData,
    val lastActivity: String,
    val authenticatedAt: String
)