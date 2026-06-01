package cn.edu.ubaa.api.local

import cn.edu.ubaa.api.SIGNIN_LOGIN_REDIRECT_LIMIT
import cn.edu.ubaa.api.SIGNIN_MY_CENTER_URL
import cn.edu.ubaa.api.extractSigninLoginNameFromUrl
import cn.edu.ubaa.api.feature.SigninApiBackend
import cn.edu.ubaa.api.resolveSigninRedirectUrl
import cn.edu.ubaa.model.dto.SigninActionResponse
import cn.edu.ubaa.model.dto.SigninClassDto
import cn.edu.ubaa.model.dto.SigninStatusResponse
import io.ktor.client.request.forms.submitForm
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import kotlin.time.Clock
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

internal class LocalSigninApiBackend : SigninApiBackend {
  private val json = Json { ignoreUnknownKeys = true }
  private val sessionMutex = Mutex()
  private val sessionCache = mutableMapOf<String, LocalSigninSession>()
  private var loginLastError: String? = null

  internal fun clearCache() {
    sessionCache.clear()
  }

  override suspend fun getTodayClasses(): Result<SigninStatusResponse> {
    val authSession =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val signinSession = runCatching { currentSession(authSession.studentId()) }.getOrNull()
    if (signinSession == null) {
      return Result.success(SigninStatusResponse(code = 200, message = "获取成功"))
    }

    return try {
      val response =
          LocalUpstreamClientProvider.shared().get(
              localUpstreamUrl(
                  "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action"
              )
          ) {
            header("sessionId", signinSession.sessionId)
            parameter("id", signinSession.userId)
            parameter("dateStr", currentSigninDate())
          }
      if (response.status != HttpStatusCode.OK) {
        return Result.success(SigninStatusResponse(code = 200, message = "获取成功"))
      }
      val payload = json.parseToJsonElement(response.bodyAsText()).jsonObject
      val classes = payload["result"]?.jsonArray?.map(::mapSigninClass).orEmpty()
      Result.success(SigninStatusResponse(code = 200, message = "获取成功", data = classes))
    } catch (_: Exception) {
      Result.success(SigninStatusResponse(code = 200, message = "获取成功"))
    }
  }

  override suspend fun performSignin(courseId: String): Result<SigninActionResponse> {
    val authSession =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val signinSession = runCatching { currentSession(authSession.studentId()) }.getOrNull()
    if (signinSession == null) {
      val error = loginLastError ?: "iclass 登录失败"
      loginLastError = null
      return Result.success(SigninActionResponse(code = 400, success = false, message = error))
    }

    return try {
      val timestamp =
          LocalUpstreamClientProvider.shared()
              .get(
                  localUpstreamUrl("http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action")
              )
              .bodyAsText()
              .let(json::parseToJsonElement)
              .jsonObject["timestamp"]
              ?.jsonPrimitive
              ?.content
      if (timestamp.isNullOrBlank()) {
        return Result.success(
            SigninActionResponse(code = 400, success = false, message = "获取服务器时间失败")
        )
      }

      val response =
          LocalUpstreamClientProvider.shared().submitForm(
              url =
                  localUpstreamUrl(
                      "http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action"
                  ),
              formParameters = Parameters.build { append("id", signinSession.userId) },
          ) {
            header("sessionId", signinSession.sessionId)
            parameter("courseSchedId", courseId)
            parameter("timestamp", timestamp)
          }
      val payload = json.parseToJsonElement(response.bodyAsText()).jsonObject
      val success =
          payload["STATUS"]?.jsonPrimitive?.intOrNull == 0 &&
              payload["result"]?.jsonObject?.get("stuSignStatus")?.jsonPrimitive?.intOrNull == 1
      Result.success(
          SigninActionResponse(
              code = if (success) 200 else 400,
              success = success,
              message =
                  sanitizeLocalSigninMessage(success, payload["ERRMSG"]?.jsonPrimitive?.content),
          )
      )
    } catch (_: Exception) {
      Result.success(SigninActionResponse(code = 400, success = false, message = "签到失败，请稍后重试"))
    }
  }

  private suspend fun currentSession(studentId: String): LocalSigninSession? {
    sessionMutex
        .withLock { sessionCache[studentId] }
        ?.let {
          return it
        }
    val created = login(studentId) ?: return null
    return sessionMutex.withLock { sessionCache.getOrPut(studentId) { created } }
  }

  private suspend fun login(studentId: String): LocalSigninSession? {
    val loginName = resolveLoginName() ?: return null
    val response =
        LocalUpstreamClientProvider.shared().get(
            localUpstreamUrl("https://iclass.buaa.edu.cn:8347/app/user/login.action")
        ) {
          parameter("password", "")
          parameter("phone", loginName)
          parameter("userLevel", "1")
          parameter("verificationType", "2")
          parameter("verificationUrl", "")
        }
    if (response.status != HttpStatusCode.OK) {
      return null
    }

    val payload = json.parseToJsonElement(response.bodyAsText()).jsonObject
    if (payload["STATUS"]?.jsonPrimitive?.intOrNull != 0) {
      loginLastError =
          payload["ERRMSG"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() } ?: "登录失败"
      return null
    }

    val result = payload["result"]?.jsonObject ?: return null
    val userId = result["id"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() } ?: return null
    val sessionId =
        result["sessionId"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() } ?: return null
    return LocalSigninSession(userId = userId, sessionId = sessionId)
  }

  private suspend fun resolveLoginName(): String? {
    val client = LocalUpstreamClientProvider.newNoRedirectClient()
    return try {
      var currentUrl = localUpstreamUrl(SIGNIN_MY_CENTER_URL)
      repeat(SIGNIN_LOGIN_REDIRECT_LIMIT) {
        val response = client.get(currentUrl)
        val finalUrl = LocalWebVpnSupport.fromWebVpnUrl(response.call.request.url.toString())
        extractSigninLoginNameFromUrl(finalUrl)?.let {
          return it
        }

        val location =
            response.headers[HttpHeaders.Location]?.let(LocalWebVpnSupport::fromWebVpnUrl)
        location?.let {
          extractSigninLoginNameFromUrl(it)?.let { loginName ->
            return loginName
          }
        }
        if (response.status.value !in 300..399 || location.isNullOrBlank()) {
          return null
        }
        currentUrl = localUpstreamUrl(resolveSigninRedirectUrl(finalUrl, location) ?: return null)
      }
      null
    } finally {
      client.close()
    }
  }
}

private data class LocalSigninSession(
    val userId: String,
    val sessionId: String,
)

private fun mapSigninClass(element: JsonElement): SigninClassDto {
  val payload = element.jsonObject
  return SigninClassDto(
      courseId = payload["id"]?.jsonPrimitive?.content ?: "",
      courseName = payload["courseName"]?.jsonPrimitive?.content ?: "",
      classBeginTime = payload["classBeginTime"]?.jsonPrimitive?.content ?: "",
      classEndTime = payload["classEndTime"]?.jsonPrimitive?.content ?: "",
      signStatus = payload["signStatus"]?.jsonPrimitive?.intOrNull ?: 0,
  )
}

private fun LocalAuthSession.studentId(): String = user.schoolid.ifBlank { username }

private fun currentSigninDate(): String {
  val date = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
  return buildString {
    append(date.year)
    append(date.month.ordinal.plus(1).toString().padStart(2, '0'))
    append(date.day.toString().padStart(2, '0'))
  }
}

internal fun sanitizeLocalSigninMessage(success: Boolean, rawMessage: String?): String {
  if (success) return rawMessage?.takeIf { it.isNotBlank() } ?: "签到成功"
  val message = rawMessage.orEmpty()
  return when {
    "已签到" in message -> "您今天已经签到过了"
    "未开始" in message -> "当前还未到签到时间"
    "不是上课时间" in message -> "当前不是上课时间，无法签到"
    "已结束" in message -> "本次签到已结束"
    "范围" in message -> "当前不在可签到范围内"
    "用户不存在" in message -> "签到账号不存在，请联系管理员"
    "课程" in message && "不存在" in message -> "未找到对应课程，请刷新后重试"
    else -> "签到失败，请稍后重试"
  }
}
