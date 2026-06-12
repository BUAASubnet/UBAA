package cn.edu.ubaa.api.local

import cn.edu.ubaa.api.ConnectionMode
import cn.edu.ubaa.api.ConnectionRuntime
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
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

internal class LocalSigninApiBackend : SigninApiBackend {
  private val json = Json { ignoreUnknownKeys = true }
  private val sessionMutex = Mutex()
  private val sessionCache = mutableMapOf<String, LocalSigninSession>()
  private var loginLastError: String? = null

  internal fun clearCache() {
    sessionCache.clear()
  }

  /** 兼容 iclass 返回的 STATUS/stuSignStatus 等字段可能为字符串或整数的情况。 */
  private fun jsonStringValue(element: JsonElement?, key: String): String? {
    val obj = element?.jsonObject ?: return null
    val prim = obj[key]?.jsonPrimitive ?: return null
    prim.contentOrNull?.let {
      return it
    }
    prim.intOrNull?.let {
      return it.toString()
    }
    prim.longOrNull?.let {
      return it.toString()
    }
    return null
  }

  private fun isStatusSuccess(jsonResponse: JsonObject): Boolean {
    val status = jsonStringValue(jsonResponse, "STATUS")
    return status == "0" || status == "200" || status == "success"
  }

  override suspend fun getTodayClasses(): Result<SigninStatusResponse> {
    return getTodayClasses(allowRetry = true)
  }

  private suspend fun getTodayClasses(allowRetry: Boolean): Result<SigninStatusResponse> {
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
      if (payload.containsKey("STATUS") && !isStatusSuccess(payload)) {
        if (allowRetry) {
          invalidateSession(authSession.studentId())
          val refreshed = runCatching { currentSession(authSession.studentId()) }.getOrNull()
          if (refreshed != null) return getTodayClasses(allowRetry = false)
        }
        return Result.success(SigninStatusResponse(code = 200, message = "获取成功"))
      }
      val classes = payload["result"]?.jsonArray?.map(::mapSigninClass).orEmpty()
      Result.success(SigninStatusResponse(code = 200, message = "获取成功", data = classes))
    } catch (_: Exception) {
      Result.success(SigninStatusResponse(code = 200, message = "获取成功"))
    }
  }

  override suspend fun performSignin(courseId: String): Result<SigninActionResponse> {
    return performSignin(courseId, allowRetry = true)
  }

  private suspend fun performSignin(
      courseId: String,
      allowRetry: Boolean,
  ): Result<SigninActionResponse> {
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
              .get(localSigninCheckinUrl("app/common/get_timestamp.action"))
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
              url = localSigninCheckinUrl("eschool/app/course/stu_scan_sign.action"),
              formParameters = Parameters.build { append("id", signinSession.userId) },
          ) {
            header("sessionId", signinSession.sessionId)
            parameter("courseSchedId", courseId)
            parameter("timestamp", timestamp)
          }
      val payload = json.parseToJsonElement(response.bodyAsText()).jsonObject
      val success =
          isStatusSuccess(payload) &&
              jsonStringValue(payload["result"]?.jsonObject, "stuSignStatus") == "1"
      val rawMessage = jsonStringValue(payload, "ERRMSG")
      if (!success) {
        if (allowRetry && rawMessage?.contains("登录") == true) {
          invalidateSession(authSession.studentId())
          val refreshed = runCatching { currentSession(authSession.studentId()) }.getOrNull()
          if (refreshed != null) return performSignin(courseId, allowRetry = false)
        }
      }
      Result.success(
          SigninActionResponse(
              code = if (success) 200 else 400,
              success = success,
              message = sanitizeLocalSigninMessage(success, rawMessage),
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

  private fun invalidateSession(studentId: String) {
    sessionCache.remove(studentId)
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
    if (!isStatusSuccess(payload)) {
      loginLastError = jsonStringValue(payload, "ERRMSG")?.takeIf { it.isNotBlank() } ?: "登录失败"
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
      // 参考 UBAANext：保持原始 URL 不变，仅在发请求时做 VPN 包装
      var rawUrl = SIGNIN_MY_CENTER_URL
      extractSigninLoginNameFromUrl(rawUrl)?.let {
        return it
      }
      repeat(SIGNIN_LOGIN_REDIRECT_LIMIT) {
        val response = client.get(localUpstreamUrl(rawUrl))
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
        rawUrl = resolveSigninRedirectUrl(finalUrl, location) ?: return null
        extractSigninLoginNameFromUrl(rawUrl)?.let { loginName ->
          return loginName
        }
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

private fun localSigninCheckinUrl(path: String): String {
  val base =
      when (ConnectionRuntime.currentMode()) {
        ConnectionMode.WEBVPN -> "https://iclass.buaa.edu.cn:8347"
        else -> "http://iclass.buaa.edu.cn:8081"
      }
  return localUpstreamUrl("$base/$path")
}

private fun mapSigninClass(element: JsonElement): SigninClassDto {
  val payload = element.jsonObject
  return SigninClassDto(
      courseId = payload["id"]?.jsonPrimitive?.content ?: "",
      courseName = payload["courseName"]?.jsonPrimitive?.content ?: "",
      classBeginTime = payload["classBeginTime"]?.jsonPrimitive?.content ?: "",
      classEndTime = payload["classEndTime"]?.jsonPrimitive?.content ?: "",
      signStatus = flexibleIntValue(payload, "signStatus"),
  )
}

/** 兼容字段可能为字符串或整数的情况，统一返回 Int。 */
private fun flexibleIntValue(obj: JsonObject, key: String): Int {
  val prim = obj[key]?.jsonPrimitive ?: return 0
  prim.intOrNull?.let {
    return it
  }
  prim.contentOrNull?.toIntOrNull()?.let {
    return it
  }
  return 0
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
