package cn.edu.ubaa.user

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.utils.VpnCipher
import cn.edu.ubaa.model.dto.UserInfo
import cn.edu.ubaa.model.dto.UserInfoResponse
import io.ktor.client.request.get
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

class UserService(
        private val sessionManager: SessionManager = GlobalSessionManager.instance,
        private val json: Json = Json { ignoreUnknownKeys = true }
) {

    private val log = LoggerFactory.getLogger(UserService::class.java)

    suspend fun fetchUserInfo(username: String): UserInfo {
        // 获取用户信息，失败抛出异常
        log.info("Fetching user info for username: {}", username)
        val session = sessionManager.requireSession(username)

        val response = session.getUserInfo()
        val body = response.bodyAsText()
        log.debug("User info response status: {}", response.status)
        log.debug("User info response body: {}", body)

        if (response.status != HttpStatusCode.OK) {
            throw UserInfoException("Failed to fetch user info. Status: ${response.status}")
        }

        val userInfoResponse =
                runCatching { json.decodeFromString<UserInfoResponse>(body) }.getOrElse { throwable
                    ->
                    log.error(
                            "Failed to parse user info response for username: {}",
                            username,
                            throwable
                    )
                    throw UserInfoException("Failed to parse user info response.")
                }

        val data = userInfoResponse.data
        if (userInfoResponse.code != 0 || data == null) {
            throw UserInfoException("Failed to retrieve user info. Code: ${userInfoResponse.code}")
        }

        return data
    }

    private suspend fun SessionManager.UserSession.getUserInfo(): HttpResponse {
        // 调用用户信息接口
        return try {
            client.get(VpnCipher.toVpnUrl("https://uc.buaa.edu.cn/api/uc/userinfo"))
        } catch (e: Exception) {
            log.error("Error while calling user info endpoint for username: {}", username, e)
            throw UserInfoException("Failed to call user info endpoint.")
        }
    }
}

class UserInfoException(message: String) : Exception(message)
