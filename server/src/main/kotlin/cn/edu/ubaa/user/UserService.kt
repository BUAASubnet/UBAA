package cn.edu.ubaa.user

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.UserInfo
import cn.edu.ubaa.model.dto.UserInfoResponse
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.get
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/** 用户信息服务。 负责从用户中心 (UC) 获取详细的个人档案数据。 */
class UserService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
  private val log = LoggerFactory.getLogger(UserService::class.java)

  /** 获取指定用户的详细资料。 */
  suspend fun fetchUserInfo(username: String): UserInfo {
    val session = sessionManager.requireSession(username)
    val response = session.getUserInfo()
    val body = response.bodyAsText()

    if (isUcSessionExpired(response, body)) {
      sessionManager.invalidateSession(username)
      throw LoginException("UC session expired")
    }
    if (response.status != HttpStatusCode.OK)
        throw UserInfoException("Fetch failed: ${response.status}")

    val resp =
        try {
          json.decodeFromString<UserInfoResponse>(body)
        } catch (_: Exception) {
          throw UserInfoException("Parse failed")
        }
    val data = resp.data
    if (resp.code != 0 || data == null) throw UserInfoException("Error code: ${resp.code}")

    return data
  }

  private suspend fun SessionManager.UserSession.getUserInfo(): HttpResponse {
    return AppObservability.observeUpstreamRequest("uc", "user_info") {
      client.get(VpnCipher.toVpnUrl("https://uc.buaa.edu.cn/api/uc/userinfo"))
    }
  }

  private fun isUcSessionExpired(response: HttpResponse, body: String): Boolean {
    if (response.status == HttpStatusCode.Unauthorized) return true
    if (response.call.request.url.toString().contains("sso.buaa.edu.cn", ignoreCase = true))
        return true
    val trimmed = body.trimStart()
    return trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
        trimmed.startsWith("<html", ignoreCase = true) ||
        body.contains("input name=\"execution\"") ||
        body.contains("统一身份认证", ignoreCase = true)
  }
}

/** 用户模块自定义异常。 */
class UserInfoException(message: String) : Exception(message)
