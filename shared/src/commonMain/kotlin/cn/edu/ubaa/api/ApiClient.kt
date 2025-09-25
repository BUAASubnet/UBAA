package cn.edu.ubaa.api

import cn.edu.ubaa.SERVER_PORT
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
 * Multi-platform HTTP client for API communication
 */
class ApiClient {
    private var httpClient: HttpClient? = null
    
    fun createClient(engine: HttpClientEngine? = null): HttpClient {
        return HttpClient(engine ?: getDefaultEngine()) {
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                })
            }
            
            install(Logging) {
                level = LogLevel.INFO
            }
            
            install(Auth) {
                bearer {
                    loadTokens {
                        // Token will be set explicitly when available
                        null
                    }
                }
            }
            
            install(HttpTimeout) {
                requestTimeoutMillis = 30_000
                connectTimeoutMillis = 10_000
                socketTimeoutMillis = 30_000
            }
            
            defaultRequest {
                url("http://localhost:$SERVER_PORT/")
            }
        }
    }
    
    fun getClient(): HttpClient {
        return httpClient ?: createClient().also { httpClient = it }
    }
    
    fun updateToken(token: String) {
        httpClient?.close()
        httpClient = HttpClient(getDefaultEngine()) {
            install(ContentNegotiation) {
                json(Json {
                    ignoreUnknownKeys = true
                    isLenient = true
                })
            }
            
            install(Logging) {
                level = LogLevel.INFO
            }
            
            install(Auth) {
                bearer {
                    loadTokens {
                        BearerTokens(token, token)
                    }
                }
            }
            
            install(HttpTimeout) {
                requestTimeoutMillis = 30_000
                connectTimeoutMillis = 10_000
                socketTimeoutMillis = 30_000
            }
            
            defaultRequest {
                url("http://localhost:$SERVER_PORT/")
            }
        }
    }
    
    fun close() {
        httpClient?.close()
        httpClient = null
    }
}

expect fun getDefaultEngine(): HttpClientEngine