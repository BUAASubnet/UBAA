package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.ExamArrangementData
import cn.edu.ubaa.model.dto.ExamResponse
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.model.dto.TermResponse
import cn.edu.ubaa.model.dto.TodayClass
import cn.edu.ubaa.model.dto.TodayScheduleResponse
import cn.edu.ubaa.model.dto.Week
import cn.edu.ubaa.model.dto.WeekResponse
import cn.edu.ubaa.model.dto.WeeklySchedule
import cn.edu.ubaa.model.dto.WeeklyScheduleResponse
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import kotlin.time.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

internal class LocalScheduleApiBackend : ScheduleApiBackend {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun getTerms(): Result<List<Term>> =
      withLocalUndergradPortalAccess(
          unsupportedMessage = "研究生账号暂不支持当前本科教务接口",
          unavailableCode = "schedule_error",
      ) {
        val response =
            LocalUpstreamClientProvider.shared().get(
                localUpstreamUrl(
                    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do"
                )
            ) {
              applyScheduleHeaders()
            }
        parseTerms(response)
      }

  override suspend fun getWeeks(termCode: String): Result<List<Week>> =
      withLocalUndergradPortalAccess(
          unsupportedMessage = "研究生账号暂不支持当前本科教务接口",
          unavailableCode = "schedule_error",
      ) {
        val response =
            LocalUpstreamClientProvider.shared().get(
                localUpstreamUrl(
                    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getTermWeeks.do"
                )
            ) {
              parameter("termCode", termCode)
              applyScheduleHeaders()
            }
        parseWeeks(response)
      }

  override suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> =
      withLocalUndergradPortalAccess(
          unsupportedMessage = "研究生账号暂不支持当前本科教务接口",
          unavailableCode = "schedule_error",
      ) {
        val response =
            LocalUpstreamClientProvider.shared().post(
                localUpstreamUrl(
                    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do"
                )
            ) {
              applyScheduleHeaders()
              setBody(
                  FormDataContent(
                      Parameters.build {
                        append("termCode", termCode)
                        append("type", "week")
                        append("week", week.toString())
                      }
                  )
              )
            }
        parseWeeklySchedule(response)
      }

  override suspend fun getTodaySchedule(): Result<List<TodayClass>> =
      withLocalUndergradPortalAccess(
          unsupportedMessage = "研究生账号暂不支持当前本科教务接口",
          unavailableCode = "schedule_error",
      ) {
        val today =
            Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date.toString()
        val response =
            LocalUpstreamClientProvider.shared().get(
                localUpstreamUrl(
                    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/teachingSchedule/detail.do"
                )
            ) {
              parameter("rq", today)
              parameter("lxdm", "student")
              applyScheduleHeaders()
            }
        parseTodaySchedule(response)
      }

  override suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData> =
      withLocalUndergradPortalAccess(
          unsupportedMessage = "研究生账号暂不支持当前本科考试接口",
          unavailableCode = "exam_error",
      ) {
        val response =
            LocalUpstreamClientProvider.shared().get(
                localUpstreamUrl(
                    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do"
                )
            ) {
              parameter("termCode", termCode)
              applyExamHeaders()
            }
        parseExamArrangement(response)
      }

  private fun HttpRequestBuilder.applyScheduleHeaders() {
    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
    header("X-Requested-With", "XMLHttpRequest")
    header(
        HttpHeaders.Referrer,
        localUpstreamUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.html"),
    )
  }

  private fun HttpRequestBuilder.applyExamHeaders() {
    header(HttpHeaders.Accept, "*/*")
    header("X-Requested-With", "XMLHttpRequest")
    header(
        HttpHeaders.Referrer,
        localUpstreamUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/home/index.html"),
    )
  }

  private suspend fun parseTerms(response: HttpResponse): Result<List<Term>> =
      parseByxtResponse(response, code = "schedule_error", defaultMessage = "课表查询失败，请稍后重试") {
        val payload = json.decodeFromString<TermResponse>(it)
        if (payload.code != "0") {
          Result.failure(localBusinessApiException("schedule_error", "课表查询失败，请稍后重试"))
        } else {
          Result.success(payload.datas)
        }
      }

  private suspend fun parseWeeks(response: HttpResponse): Result<List<Week>> =
      parseByxtResponse(response, code = "schedule_error", defaultMessage = "课表查询失败，请稍后重试") {
        val payload = json.decodeFromString<WeekResponse>(it)
        Result.success(payload.datas)
      }

  private suspend fun parseWeeklySchedule(response: HttpResponse): Result<WeeklySchedule> =
      parseByxtResponse(response, code = "schedule_error", defaultMessage = "课表查询失败，请稍后重试") {
        val payload = json.decodeFromString<WeeklyScheduleResponse>(it)
        Result.success(payload.datas)
      }

  private suspend fun parseTodaySchedule(response: HttpResponse): Result<List<TodayClass>> =
      parseByxtResponse(response, code = "schedule_error", defaultMessage = "课表查询失败，请稍后重试") {
        val payload = json.decodeFromString<TodayScheduleResponse>(it)
        Result.success(payload.datas)
      }

  private suspend fun parseExamArrangement(response: HttpResponse): Result<ExamArrangementData> =
      parseByxtResponse(response, code = "exam_error", defaultMessage = "考试信息查询失败，请稍后重试") {
        val payload = json.decodeFromString<ExamResponse>(it)
        if (payload.code != "0") {
          Result.failure(localBusinessApiException("exam_error", "考试信息查询失败，请稍后重试"))
        } else {
          Result.success(ExamArrangementData(arranged = payload.datas))
        }
      }

  private suspend fun <T> parseByxtResponse(
      response: HttpResponse,
      code: String,
      defaultMessage: String,
      parse: suspend (String) -> Result<T>,
  ): Result<T> {
    return try {
      val body = response.bodyAsText()
      if (isLocalByxtSessionExpired(response, body)) {
        clearLocalConnectionSession()
        return Result.failure(localUnauthenticatedApiException())
      }
      if (response.status != HttpStatusCode.OK) {
        return Result.failure(localBusinessApiException(code, defaultMessage, response.status))
      }
      parse(body)
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException(defaultMessage))
    }
  }
}

internal suspend fun <T> withLocalUndergradPortalAccess(
    unsupportedMessage: String,
    unavailableCode: String,
    block: suspend () -> Result<T>,
): Result<T> {
  if (LocalAuthSessionStore.get() == null) {
    return Result.failure(localUnauthenticatedApiException())
  }
  return try {
    when (probeLocalUndergradPortal()) {
      LocalUndergradPortalProbeResult.UNDERGRAD_READY -> block()
      LocalUndergradPortalProbeResult.GRADUATE_READY ->
          Result.failure(
              ApiCallException(
                  message = unsupportedMessage,
                  status = HttpStatusCode.Forbidden,
                  code = "unsupported_portal",
              )
          )
      LocalUndergradPortalProbeResult.SSO_REQUIRED -> {
        clearLocalConnectionSession()
        Result.failure(localUnauthenticatedApiException())
      }
      LocalUndergradPortalProbeResult.UNAVAILABLE ->
          Result.failure(
              localBusinessApiException(
                  unavailableCode,
                  userFacingMessageForCode(unavailableCode, HttpStatusCode.ServiceUnavailable),
                  HttpStatusCode.ServiceUnavailable,
              )
          )
    }
  } catch (e: Exception) {
    Result.failure(
        e.toUserFacingApiException(
            userFacingMessageForCode(unavailableCode, HttpStatusCode.ServiceUnavailable)
        )
    )
  }
}

internal enum class LocalUndergradPortalProbeResult {
  UNDERGRAD_READY,
  GRADUATE_READY,
  SSO_REQUIRED,
  UNAVAILABLE,
}

internal suspend fun probeLocalUndergradPortal(): LocalUndergradPortalProbeResult {
  val response =
      LocalUpstreamClientProvider.shared()
          .get(
              localUpstreamUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do")
          )
  val body = response.bodyAsText()
  return classifyLocalUndergradResponse(response.status, response.call.request.url.toString(), body)
}

internal fun classifyLocalUndergradResponse(
    status: HttpStatusCode,
    finalUrl: String,
    body: String,
): LocalUndergradPortalProbeResult {
  if (isLocalSsoRedirect(status, finalUrl, body))
      return LocalUndergradPortalProbeResult.SSO_REQUIRED
  if (status != HttpStatusCode.OK) return LocalUndergradPortalProbeResult.UNAVAILABLE

  val trimmed = body.trimStart()
  if (finalUrl.contains("/jwapp/sys/byrhmhsy/", ignoreCase = true)) {
    return if (trimmed.startsWith("{") || trimmed.startsWith("[") || body.isBlank()) {
      LocalUndergradPortalProbeResult.GRADUATE_READY
    } else {
      LocalUndergradPortalProbeResult.UNAVAILABLE
    }
  }

  if (
      trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
          trimmed.startsWith("<html", ignoreCase = true)
  ) {
    return LocalUndergradPortalProbeResult.UNAVAILABLE
  }

  return if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
    LocalUndergradPortalProbeResult.UNDERGRAD_READY
  } else {
    LocalUndergradPortalProbeResult.UNAVAILABLE
  }
}

internal fun isLocalByxtSessionExpired(response: HttpResponse, body: String): Boolean =
    classifyLocalUndergradResponse(response.status, response.call.request.url.toString(), body) !=
        LocalUndergradPortalProbeResult.UNDERGRAD_READY

private fun isLocalSsoRedirect(status: HttpStatusCode, finalUrl: String, body: String): Boolean {
  if (status == HttpStatusCode.Unauthorized) return true
  if (localIsSsoUrl(finalUrl)) return true
  val trimmed = body.trimStart()
  if (trimmed.startsWith("<!DOCTYPE html", ignoreCase = true)) {
    return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
  }
  if (trimmed.startsWith("<html", ignoreCase = true)) {
    return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
  }
  return false
}

internal fun localBusinessApiException(
    code: String,
    defaultMessage: String,
    status: HttpStatusCode = HttpStatusCode.InternalServerError,
): ApiCallException =
    ApiCallException(
        message = userFacingMessageForCode(code, status).ifBlank { defaultMessage },
        status = status,
        code = code,
    )
