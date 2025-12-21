package cn.edu.ubaa.api

import cn.edu.ubaa.CLIENT_PORT
import cn.edu.ubaa.SERVER_HOST
import io.ktor.client.*
import io.ktor.client.engine.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.auth.*
import io.ktor.client.plugins.auth.providers.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json

/** Multi-platform HTTP client for API communication */
class ApiClient {
    private var httpClient: HttpClient? = null
    private var cachedToken: String? = TokenStore.get()

    private fun createClient(
            engine: HttpClientEngine? = null,
            token: String? = cachedToken
    ): HttpClient {
        return HttpClient(engine ?: getDefaultEngine()) {
            install(ContentNegotiation) {
                json(
                        Json {
                            ignoreUnknownKeys = true
                            isLenient = true
                        }
                )
            }

            install(Logging) { level = LogLevel.INFO }

            install(Auth) { bearer { loadTokens { token?.let { BearerTokens(it, it) } } } }

            install(HttpTimeout) {
                requestTimeoutMillis = 30_000
                connectTimeoutMillis = 10_000
                socketTimeoutMillis = 30_000
            }

            defaultRequest { url("$SERVER_HOST:$CLIENT_PORT/") }
        }
    }

    fun getClient(): HttpClient {
        return httpClient ?: createClient(token = cachedToken).also { httpClient = it }
    }

    fun updateToken(token: String) {
        cachedToken = token
        TokenStore.save(token)
        httpClient?.close()
        httpClient = createClient(token = token)
    }

    fun close() {
        httpClient?.close()
        httpClient = null
        cachedToken = null
    }
}

expect fun getDefaultEngine(): HttpClientEngine
