package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.body
import io.ktor.client.request.*
import io.ktor.http.*
import kotlinx.serialization.Serializable

/** 认证服务：登录、注销、会话管理 */
object ApiClientProvider {
    val shared: ApiClient by lazy { ApiClient() }
}

@Serializable
data class SessionStatusResponse(
        val user: UserData,
        val lastActivity: String,
        val authenticatedAt: String
)

class AuthService(private val apiClient: ApiClient = ApiClientProvider.shared) {

    fun applyStoredToken() {
        TokenStore.get()?.let { apiClient.updateToken(it) }
    }

    /** 预加载登录状态：为当前客户端创建专属会话，获取验证码（如果需要） */
    suspend fun preloadLoginState(): Result<LoginPreloadResponse> {
        return try {
            val clientId = ClientIdStore.getOrCreate()
            val response =
                    apiClient.getClient().post("api/v1/auth/preload") {
                        contentType(ContentType.Application.Json)
                        setBody(LoginPreloadRequest(clientId))
                    }
            when (response.status) {
                HttpStatusCode.OK -> {
                    Result.success(response.body<LoginPreloadResponse>())
                }
                else -> {
                    Result.failure(Exception("Failed to preload login state: ${response.status}"))
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /** 登录：使用 preload 时创建的会话 */
    suspend fun login(
            username: String,
            password: String,
            captcha: String? = null,
            execution: String? = null
    ): Result<LoginResponse> {
        return try {
            val clientId = ClientIdStore.get()
            val response =
                    apiClient.getClient().post("api/v1/auth/login") {
                        contentType(ContentType.Application.Json)
                        setBody(LoginRequest(username, password, captcha, execution, clientId))
                    }

            when (response.status) {
                HttpStatusCode.OK -> {
                    val loginResponse = response.body<LoginResponse>()
                    // 更新 Token，保证后续认证
                    apiClient.updateToken(loginResponse.token)
                    TokenStore.save(loginResponse.token)
                    Result.success(loginResponse)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = runCatching { response.body<ApiErrorResponse>() }.getOrNull()
                    Result.failure(Exception(error?.error?.message ?: "Unauthorized"))
                }
                HttpStatusCode.UnprocessableEntity -> { // 422 - 需要验证码
                    val captchaResponse = response.body<CaptchaRequiredResponse>()
                    Result.failure(
                            CaptchaRequiredClientException(
                                    captchaResponse.captcha,
                                    captchaResponse.execution,
                                    captchaResponse.message
                            )
                    )
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
        return safeApiCall { apiClient.getClient().get("api/v1/auth/status") }
    }

    suspend fun logout(): Result<Unit> {
        return try {
            // 尝试服务端注销
            val serverResponse = apiClient.getClient().post("api/v1/auth/logout")

            // 无论服务端结果如何，尝试 SSO 注销
            try {
                val ssoResponse = apiClient.getClient().get("https://sso.buaa.edu.cn/logout")
                println("SSO logout response: ${ssoResponse.status}")
            } catch (ssoException: Exception) {
                println(
                        "SSO logout failed (this is expected in some environments): ${ssoException.message}"
                )
            }

            // 始终清理本地状态
            TokenStore.clear()
            apiClient.close()
            Result.success(Unit)
        } catch (e: Exception) {
            // 网络异常时也要清理本地状态
            TokenStore.clear()
            apiClient.close()
            Result.failure(e)
        }
    }
}

/** 用户服务：获取用户信息 */
class UserService(private val apiClient: ApiClient = ApiClientProvider.shared) {
    suspend fun getUserInfo(): Result<UserInfo> {
        return safeApiCall { apiClient.getClient().get("api/v1/user/info") }
    }
}
