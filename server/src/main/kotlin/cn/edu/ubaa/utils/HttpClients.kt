package cn.edu.ubaa.utils

import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import java.time.Duration

object HttpClients {
    /**
     * 共享 HttpClient，用于无状态的内部请求（如获取验证码）。 禁止用于需要用户会话（Cookie）的请求。
     *
     * 代理配置：通过环境变量 HTTP_PROXY 或 HTTPS_PROXY 设置 例如: HTTP_PROXY=http://127.0.0.1:7890 SSL 证书信任：通过环境变量
     * TRUST_ALL_CERTS=true 禁用证书验证（仅用于开发环境）
     */
    val sharedClient by lazy {
        HttpClient(CIO) {
            engine {
                val proxyUrl =
                        System.getenv("HTTPS_PROXY")
                                ?: System.getenv("HTTP_PROXY") ?: System.getenv("https_proxy")
                                        ?: System.getenv("http_proxy")
                if (!proxyUrl.isNullOrBlank()) {
                    proxy = io.ktor.client.engine.ProxyBuilder.http(io.ktor.http.Url(proxyUrl))
                }

                // 开发环境下信任所有证书（用于代理 MITM 场景）
                val trustAllCerts = System.getenv("TRUST_ALL_CERTS")?.lowercase() == "true"
                if (trustAllCerts) {
                    https {
                        trustManager =
                                object : javax.net.ssl.X509TrustManager {
                                    override fun checkClientTrusted(
                                            chain: Array<java.security.cert.X509Certificate>?,
                                            authType: String?
                                    ) {}
                                    override fun checkServerTrusted(
                                            chain: Array<java.security.cert.X509Certificate>?,
                                            authType: String?
                                    ) {}
                                    override fun getAcceptedIssuers():
                                            Array<java.security.cert.X509Certificate> = arrayOf()
                                }
                    }
                }
            }

            install(HttpTimeout) {
                requestTimeoutMillis = Duration.ofSeconds(10).toMillis()
                connectTimeoutMillis = Duration.ofSeconds(5).toMillis()
                socketTimeoutMillis = Duration.ofSeconds(10).toMillis()
            }
        }
    }
}
