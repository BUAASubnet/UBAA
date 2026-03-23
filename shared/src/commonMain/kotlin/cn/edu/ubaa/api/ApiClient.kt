package cn.edu.ubaa.api

import cn.edu.ubaa.BuildKonfig
import cn.edu.ubaa.model.dto.TokenRefreshRequest
import cn.edu.ubaa.model.dto.TokenRefreshResponse
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.auth.*
import io.ktor.client.plugins.auth.providers.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json

/**
 * API 通信的多平台 HTTP 客户端。 负责管理 Ktor HttpClient 的创建、配置（序列化、日志、认证、超时）以及令牌更新。
 *
 * @param engine 指定的 HTTP 引擎，若为 null 则使用平台默认引擎。
 */
class ApiClient(private val engine: HttpClientEngine? = null) {
  private var httpClient: HttpClient? = null
  private var cachedTokens: BearerTokens? = AuthTokensStore.get()?.toBearerTokens()
  private val refreshMutex = Mutex()

  /**
   * 创建并配置一个新的 HttpClient 实例。
   *
   * @param engine 指定的 HTTP 引擎，若为 null 则使用构造函数中定义的引擎或平台默认引擎。
   * @return 配置好的 HttpClient 实例。
   */
  private fun createClient(engine: HttpClientEngine? = this.engine): HttpClient {
    return HttpClient(engine ?: getDefaultEngine()) {
      // 配置 JSON 序列化
      install(ContentNegotiation) {
        json(
            Json {
              ignoreUnknownKeys = true // 忽略未定义的键
              isLenient = true // 宽松解析
            }
        )
      }

      // 配置请求/响应日志
      install(Logging) { level = LogLevel.INFO }

      // 配置 Bearer 认证
      install(Auth) {
        bearer {
          loadTokens { cachedTokens }
          refreshTokens {
            val expiredTokens = oldTokens ?: return@refreshTokens null
            val refreshToken = expiredTokens.refreshToken ?: return@refreshTokens null
            refreshMutex.withLock {
              val latestTokens = cachedTokens
              if (latestTokens != null && latestTokens.refreshToken != expiredTokens.refreshToken) {
                return@withLock latestTokens
              }

              val refreshResponse =
                  client.post("api/v1/auth/refresh") {
                    markAsRefreshTokenRequest()
                    contentType(ContentType.Application.Json)
                    setBody(TokenRefreshRequest(refreshToken))
                  }
              if (refreshResponse.status != HttpStatusCode.OK) {
                clearAuthTokens()
                return@withLock null
              }

              val refreshedTokens =
                  refreshResponse.body<TokenRefreshResponse>().toStoredAuthTokens()
              updateTokens(refreshedTokens)
              refreshedTokens.toBearerTokens()
            }
          }
        }
      }

      // 配置超时时间
      install(HttpTimeout) {
        requestTimeoutMillis = 30_000
        connectTimeoutMillis = 10_000
        socketTimeoutMillis = 30_000
      }

      // 设置默认基准 URL
      defaultRequest { url(BuildKonfig.API_ENDPOINT) }
    }
  }

  /**
   * 获取当前 HttpClient 实例。如果实例不存在，则创建一个新的。
   *
   * @return 当前可用的 HttpClient 实例。
   */
  fun getClient(): HttpClient {
    if (cachedTokens == null) {
      cachedTokens = AuthTokensStore.get()?.toBearerTokens()
    }
    return httpClient ?: createClient().also { httpClient = it }
  }

  /** 从持久化存储重新加载令牌到当前客户端。 */
  fun applyStoredTokens() {
    cachedTokens = AuthTokensStore.get()?.toBearerTokens()
  }

  /**
   * 更新认证令牌。 会保存新令牌到存储中，并刷新当前内存态。
   *
   * @param tokens 新的认证令牌集合。
   */
  fun updateTokens(tokens: StoredAuthTokens) {
    AuthTokensStore.save(tokens)
    cachedTokens = tokens.toBearerTokens()
  }

  /** 清理当前认证令牌。 */
  fun clearAuthTokens() {
    AuthTokensStore.clear()
    cachedTokens = null
  }

  /** 关闭并释放 HttpClient 资源。 */
  fun close() {
    httpClient?.close()
    httpClient = null
    cachedTokens = null
  }
}

private fun StoredAuthTokens.toBearerTokens(): BearerTokens =
    BearerTokens(accessToken = accessToken, refreshToken = refreshToken)

private fun TokenRefreshResponse.toStoredAuthTokens(): StoredAuthTokens =
    StoredAuthTokens(
        accessToken = accessToken,
        refreshToken = refreshToken,
        accessTokenExpiresAt = accessTokenExpiresAt,
        refreshTokenExpiresAt = refreshTokenExpiresAt,
    )

/** 获取当前平台的默认 HTTP 引擎。 在各平台（Android, iOS, JVM 等）对应的实现文件中定义。 */
expect fun getDefaultEngine(): HttpClientEngine
