package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.body
import io.ktor.client.request.*
import io.ktor.http.*
import kotlinx.serialization.Serializable

/** 认证服务提供者，管理全局共享的 ApiClient。 */
object ApiClientProvider {
  /** 全局共享的 ApiClient 实例。 */
  val shared: ApiClient by lazy { ApiClient() }
}

/**
 * 会话状态响应。
 *
 * @property user 用户基本身份信息。
 * @property lastActivity 最后活动时间。
 * @property authenticatedAt 认证时间。
 */
@Serializable
data class SessionStatusResponse(
  val user: UserData,
  val lastActivity: String,
  val authenticatedAt: String,
)

/**
 * 认证服务，负责登录、预加载、注销及会话状态查询。
 *
 * @param apiClient 使用的 ApiClient 实例，默认为单例 shared。
 */
class AuthService(private val apiClient: ApiClient = ApiClientProvider.shared) {

  /** 将本地存储的令牌应用到当前 ApiClient 中。 */
  fun applyStoredToken() {
    TokenStore.get()?.let { apiClient.updateToken(it) }
  }

  /**
   * 预加载登录状态。 为当前客户端创建或关联专属会话，并获取登录所需的附加信息（如验证码）。
   *
   * @return 预加载结果，包含验证码信息或已登录的令牌。
   */
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

  /**
   * 执行用户登录。 使用 preload 时创建的会话和执行标识（execution）进行认证。
   *
   * @param username 用户名（学号）。
   * @param password 密码。
   * @param captcha 验证码（如果需要）。
   * @param execution SSO 流程执行标识。
   * @return 登录结果，成功则返回 LoginResponse 并自动更新 ApiClient 令牌。
   */
  suspend fun login(
    username: String,
    password: String,
    captcha: String? = null,
    execution: String? = null,
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
              captchaResponse.message,
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

  /**
   * 查询当前会话状态。
   *
   * @return 包含用户信息和活动时间的 SessionStatusResponse。
   */
  suspend fun getAuthStatus(): Result<SessionStatusResponse> {
    return safeApiCall { apiClient.getClient().get("api/v1/auth/status") }
  }

  /**
   * 注销当前用户。 会尝试通知服务端和上游 SSO 注销，并清理本地令牌和 ApiClient 状态。
   *
   * @return 注销操作结果。
   */
  suspend fun logout(): Result<Unit> {
    return try {
      // 尝试服务端注销
      val serverResponse = apiClient.getClient().post("api/v1/auth/logout")

      // 无论服务端结果如何，尝试 SSO 注销
      try {
        val ssoResponse = apiClient.getClient().get("https://sso.buaa.edu.cn/logout")
        println("SSO 注销响应: ${ssoResponse.status}")
      } catch (ssoException: Exception) {
        println("SSO 注销失败（在某些网络环境下符合预期）: ${ssoException.message}")
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

/**
 * 用户相关服务，负责获取用户的详细考籍或个人信息。
 *
 * @param apiClient 使用的 ApiClient 实例。
 */
class UserService(private val apiClient: ApiClient = ApiClientProvider.shared) {
  /**
   * 获取当前用户的详细资料信息。
   *
   * @return 包含用户姓名、学号等信息的 UserInfo。
   */
  suspend fun getUserInfo(): Result<UserInfo> {
    return safeApiCall { apiClient.getClient().get("api/v1/user/info") }
  }
}
