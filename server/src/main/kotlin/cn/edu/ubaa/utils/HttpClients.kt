package cn.edu.ubaa.utils

import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout

/** 共享 HTTP 客户端工厂。 提供无状态的全局共享客户端，适用于公共资源（如验证码图片、更新检测）的请求。 */
object HttpClients {
  /** 共享的 HttpClient 实例。 配置了自动代理探测和超时控制。 警告：禁止用于需要维持特定用户会话（Cookie）的请求。 */
  val sharedClient by lazy {
    HttpClient(CIO) {
      engine {
        // 自动加载系统代理配置
        val proxyUrl = System.getenv("HTTPS_PROXY") ?: System.getenv("HTTP_PROXY")
        if (!proxyUrl.isNullOrBlank()) {
          proxy = io.ktor.client.engine.ProxyBuilder.http(io.ktor.http.Url(proxyUrl))
        }

        // 开发环境下支持信任所有证书
        if (System.getenv("TRUST_ALL_CERTS")?.lowercase() == "true") {
          https {
            trustManager =
              object : javax.net.ssl.X509TrustManager {
                override fun checkClientTrusted(
                  c: Array<java.security.cert.X509Certificate>?,
                  a: String?,
                ) {}

                override fun checkServerTrusted(
                  c: Array<java.security.cert.X509Certificate>?,
                  a: String?,
                ) {}

                override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> =
                  arrayOf()
              }
          }
        }
      }

      install(HttpTimeout) {
        requestTimeoutMillis = 10_000
        connectTimeoutMillis = 5_000
      }
    }
  }
}
