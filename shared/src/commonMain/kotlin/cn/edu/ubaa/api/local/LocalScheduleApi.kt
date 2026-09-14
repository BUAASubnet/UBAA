package cn.edu.ubaa.api.local

import cn.edu.ubaa.api.auth.ApiCallException
import cn.edu.ubaa.api.auth.toUserFacingApiException
import cn.edu.ubaa.api.auth.userFacingMessageForCode
import cn.edu.ubaa.api.feature.GraduateScheduleLoadException
import cn.edu.ubaa.api.feature.ScheduleApiBackend
import cn.edu.ubaa.api.feature.fetchGraduateSchedule
import cn.edu.ubaa.model.dto.ExamArrangementData
import cn.edu.ubaa.model.dto.ExamResponse
import cn.edu.ubaa.model.dto.GraduateSchedule
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.model.dto.TermResponse
import cn.edu.ubaa.model.dto.TodayClass
import cn.edu.ubaa.model.dto.TodayScheduleResponse
import cn.edu.ubaa.model.dto.Week
import cn.edu.ubaa.model.dto.WeekResponse
import cn.edu.ubaa.model.dto.WeeklySchedule
import cn.edu.ubaa.model.dto.WeeklyScheduleResponse
import cn.edu.ubaa.repository.SemesterSchedule
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
import kotlinx.coroutines.CancellationException
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json

internal class LocalScheduleApiBackend : ScheduleApiBackend {
  private val json = Json { ignoreUnknownKeys = true }
  private var graduateSession: Pair<String, String>? = null

  override suspend fun importSemester(termCode: String?): Result<SemesterSchedule> =
      withScheduleAccess(
          graduate = {
            val data = graduateSchedule(termCode)
            val terms = data.terms()
            val term =
                if (termCode == null) terms.firstOrNull { it.selected } ?: terms.firstOrNull()
                else terms.firstOrNull { it.itemCode == termCode }
            requireNotNull(term) { "研究生系统未返回所选学期" }
            val weeks = data.weeks(term.itemCode, graduateToday())
            Result.success(
                SemesterSchedule(
                    terms,
                    term.itemCode,
                    weeks,
                    weeks.associate {
                      it.serialNumber to data.weekly(term.itemCode, it.serialNumber)
                    },
                )
            )
          }
      ) {
        super.importSemester(termCode)
      }

  override suspend fun getTerms(): Result<List<Term>> =
      withScheduleAccess(
          graduate = { Result.success(graduateSchedule().terms()) },
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
      withScheduleAccess(
          graduate = {
            Result.success(graduateSchedule(termCode).weeks(termCode, graduateToday()))
          },
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
      withScheduleAccess(
          graduate = { Result.success(graduateSchedule(termCode).weekly(termCode, week)) },
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
      withScheduleAccess(
          graduate = { Result.success(graduateSchedule().today(graduateToday())) },
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

  private suspend fun graduateSchedule(termCode: String? = null): GraduateSchedule =
      fetchGraduateSchedule(LocalUpstreamClientProvider.shared(), ::localUpstreamUrl, termCode)

  private suspend fun <T> withScheduleAccess(
      graduate: suspend () -> Result<T>,
      block: suspend () -> Result<T>,
  ): Result<T> {
    val session =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val key = session.username to session.authenticatedAt
    if (graduateSession != key) {
      val undergraduate =
          try {
            if (probeLocalUndergradPortal() == LocalUndergradPortalProbeResult.UNDERGRAD_READY)
                block()
            else null
          } catch (e: CancellationException) {
            throw e
          } catch (_: Exception) {
            null
          }
      if (undergraduate?.isSuccess == true) return undergraduate
    }
    // 本科门户或 GSMIS 探测失败不代表 GSMIS 我的课表不可用，直接验证真正的数据源。
    return try {
      graduate().also { if (it.isSuccess) graduateSession = key }
    } catch (e: CancellationException) {
      throw e
    } catch (e: GraduateScheduleLoadException) {
      Result.failure(
          ApiCallException(
              e.message ?: "研究生课表加载失败",
              HttpStatusCode.BadGateway,
              "schedule_error",
              cause = e,
          )
      )
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("研究生课表转换失败（${e::class.simpleName}）"))
    }
  }

  private fun graduateToday() =
      Clock.System.now().toLocalDateTime(TimeZone.of("Asia/Shanghai")).date

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
        if (code == "schedule_error") {
          // 还要尝试 GSMIS 我的课表，不能因本科子系统不可用而清理主会话。
          return Result.failure(
              localBusinessApiException(code, defaultMessage, HttpStatusCode.BadGateway)
          )
        }
        return Result.failure(resolveLocalBusinessAuthenticationFailure(code))
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
      LocalUndergradPortalProbeResult.SSO_REQUIRED ->
          Result.failure(resolveLocalBusinessAuthenticationFailure(unavailableCode))
      LocalUndergradPortalProbeResult.UNAVAILABLE ->
          Result.failure(
              localBusinessApiException(
                  unavailableCode,
                  userFacingMessageForCode(unavailableCode, HttpStatusCode.ServiceUnavailable),
                  HttpStatusCode.ServiceUnavailable,
              )
          )
    }
  } catch (e: CancellationException) {
    throw e
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
