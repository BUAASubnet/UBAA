package cn.edu.ubaa.api

import cn.edu.ubaa.BuildKonfig
import io.ktor.client.*
import io.ktor.client.engine.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.auth.*
import io.ktor.client.plugins.auth.providers.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json

/**
 * API 通信的多平台 HTTP 客户端。 负责管理 Ktor HttpClient 的创建、配置（序列化、日志、认证、超时）以及令牌更新。
 *
 * @param engine 指定的 HTTP 引擎，若为 null 则使用平台默认引擎。
 */
class ApiClient(private val engine: HttpClientEngine? = null) {
  private var httpClient: HttpClient? = null
  private var cachedToken: String? = TokenStore.get()

  /**
   * 创建并配置一个新的 HttpClient 实例。
   *
   * @param engine 指定的 HTTP 引擎，若为 null 则使用构造函数中定义的引擎或平台默认引擎。
   * @param token 认证令牌（Bearer Token），用于请求头验证。默认使用缓存的令牌。
   * @return 配置好的 HttpClient 实例。
   */
  private fun createClient(
    engine: HttpClientEngine? = this.engine,
    token: String? = cachedToken,
  ): HttpClient {
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
      install(Auth) { bearer { loadTokens { token?.let { BearerTokens(it, it) } } } }

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
    return httpClient ?: createClient(token = cachedToken).also { httpClient = it }
  }

  /**
   * 更新认证令牌。 会保存新令牌到存储中，并关闭旧的 HttpClient 实例以重新创建带新令牌的实例。
   *
   * @param token 新的认证令牌字符串。
   */
  fun updateToken(token: String) {
    cachedToken = token
    TokenStore.save(token)
    httpClient?.close()
    httpClient = createClient(token = token)
  }

  /** 关闭并释放 HttpClient 资源。 */
  fun close() {
    httpClient?.close()
    httpClient = null
    cachedToken = null
  }
}

/** 获取当前平台的默认 HTTP 引擎。 在各平台（Android, iOS, JVM 等）对应的实现文件中定义。 */
expect fun getDefaultEngine(): HttpClientEngine
