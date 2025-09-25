package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.LoginRequest
import io.ktor.client.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.cookies.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import org.jsoup.Jsoup

class AuthService {

    private val client = HttpClient(CIO) {
        install(HttpCookies)
        // We need to handle redirects manually to find the token
        followRedirects = false
        expectSuccess = false
    }

    suspend fun login(request: LoginRequest): String {
        val loginUrl = "https://sso.buaa.edu.cn/login"

        // 1. Get the execution token from the login page HTML
        val loginPageResponse = client.get(loginUrl) {
            headers {
                append(HttpHeaders.UserAgent, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3")
            }
        }

        if (loginPageResponse.status != HttpStatusCode.OK) {
            throw LoginException("Failed to load login page. Status: ${loginPageResponse.status}")
        }

        val loginPageHtml = loginPageResponse.bodyAsText()
        val doc = Jsoup.parse(loginPageHtml)
        val execution = doc.select("input[name=execution]").`val`()

        if (execution.isNullOrBlank()) {
            // Check for existing login error messages on the page
            val errorTip = doc.select(".tip-text").text()
            if (errorTip.isNotBlank()) {
                throw LoginException("Login failed: $errorTip")
            }
            throw LoginException("Could not find execution token on login page.")
        }

        // 2. Post the credentials to log in
        var response = client.post(loginUrl) {
            headers {
                append(HttpHeaders.UserAgent, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3")
            }
            setBody(FormDataContent(Parameters.build {
                append("username", request.username)
                append("password", request.password)
                append("submit", "登录")
                append("type", "username_password")
                append("execution", execution)
                append("_eventId", "submit")
            }))
        }

        // 3. Follow redirects until we find the final token
        var redirectCount = 0
        while (response.status == HttpStatusCode.Found) {
            if (redirectCount++ > 10) throw LoginException("Too many redirects.")

            val location = response.headers[HttpHeaders.Location]
                ?: throw LoginException("Login failed: Redirect location header not found.")

            // The token is in the query parameter of one of the redirects
            if ("?token=" in location) {
                // Here we get the school's token. For now, we return it directly.
                // In a real scenario, we would exchange this for our own server's session token.
                val schoolToken = location.substringAfter("?token=")
                // We should complete the final redirect to ensure the session is fully established
                client.get(location)
                // For now, we will just generate a placeholder for our own token
                return "ubaa_session_token_placeholder_for_${request.username}"
            }

            response = client.get(location)
        }

        // If we exit the loop and haven't found a token, something went wrong.
        val finalHtml = response.bodyAsText()
        val finalDoc = Jsoup.parse(finalHtml)
        val errorTip = finalDoc.select(".tip-text").text()
        if (errorTip.isNotBlank()) {
            throw LoginException("Login failed: $errorTip")
        }

        throw LoginException("Login failed. Could not obtain token after redirects. Final status: ${response.status}")
    }
}

class LoginException(message: String) : Exception(message)
