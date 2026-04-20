package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.SigninActionResponse
import cn.edu.ubaa.model.dto.SigninClassDto
import cn.edu.ubaa.model.dto.SigninStatusResponse
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.time.Clock

internal class LocalSigninApiBackend : SigninApiBackend {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun getTodayClasses(): Result<SigninStatusResponse> {
    val authSession = LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val signinSession = runCatching { login(authSession.studentId()) }.getOrNull()
    if (signinSession == null) {
      return Result.success(SigninStatusResponse(code = 200, message = "获取成功"))
    }

    return try {
      val response =
          LocalUpstreamClientProvider.shared().get(
              localUpstreamUrl("https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action")
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
    val authSession = LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val signinSession = runCatching { login(authSession.studentId()) }.getOrNull()
    if (signinSession == null) {
      return Result.success(SigninActionResponse(code = 400, success = false, message = "登录失败"))
    }

    return try {
      val timestamp =
          LocalUpstreamClientProvider.shared()
              .get(localUpstreamUrl("http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action"))
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
          LocalUpstreamClientProvider.shared().post(
              localUpstreamUrl("http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action")
          ) {
            parameter("courseSchedId", courseId)
            parameter("timestamp", timestamp)
            setBody(FormDataContent(Parameters.build { append("id", signinSession.userId) }))
          }
      val payload = json.parseToJsonElement(response.bodyAsText()).jsonObject
      val success =
          payload["STATUS"]?.jsonPrimitive?.intOrNull == 0 &&
              payload["result"]
                  ?.jsonObject
                  ?.get("stuSignStatus")
                  ?.jsonPrimitive
                  ?.intOrNull == 1
      Result.success(
          SigninActionResponse(
              code = if (success) 200 else 400,
              success = success,
              message = sanitizeLocalSigninMessage(success, payload["ERRMSG"]?.jsonPrimitive?.content),
          )
      )
    } catch (_: Exception) {
      Result.success(SigninActionResponse(code = 400, success = false, message = "签到失败，请稍后重试"))
    }
  }

  private suspend fun login(studentId: String): LocalSigninSession? {
    val response =
        LocalUpstreamClientProvider.shared().get(localUpstreamUrl("https://iclass.buaa.edu.cn:8347/app/user/login.action")) {
          parameter("password", "")
          parameter("phone", studentId)
          parameter("userLevel", "1")
          parameter("verificationType", "2")
          parameter("verificationUrl", "")
        }
    if (response.status != HttpStatusCode.OK) {
      return null
    }

    val payload = json.parseToJsonElement(response.bodyAsText()).jsonObject
    if (payload["STATUS"]?.jsonPrimitive?.intOrNull != 0) {
      return null
    }

    val result = payload["result"]?.jsonObject ?: return null
    val userId = result["id"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() } ?: return null
    val sessionId =
        result["sessionId"]?.jsonPrimitive?.content?.takeIf { it.isNotBlank() } ?: return null
    return LocalSigninSession(userId = userId, sessionId = sessionId)
  }
}

private data class LocalSigninSession(
    val userId: String,
    val sessionId: String,
)

private fun mapSigninClass(element: kotlinx.serialization.json.JsonElement): SigninClassDto {
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
    "课程" in message && "不存在" in message -> "未找到对应课程，请刷新后重试"
    else -> "签到失败，请稍后重试"
  }
}
