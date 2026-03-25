package cn.edu.ubaa.schedule

import cn.edu.ubaa.auth.ByxtService
import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.auth.AcademicPortalProbeResult
import cn.edu.ubaa.auth.AcademicPortalType
import cn.edu.ubaa.auth.UnsupportedAcademicPortalException
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/** 课表业务服务。 负责与教务系统 (BYXT) 通信，获取学期、周次及排课数据。 */
class ScheduleService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
  private val log = LoggerFactory.getLogger(ScheduleService::class.java)

  /** 设置请求头以匹配教务系统的 AJAX 请求要求。 */
  private fun HttpRequestBuilder.applyScheduleHeaders() {
    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
    header("X-Requested-With", "XMLHttpRequest")
    header(
        HttpHeaders.Referrer,
        VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.html"),
    )
  }

  /** 获取用户可选的所有学期列表。 */
  suspend fun fetchTerms(username: String): List<Term> {
    val session = sessionManager.requireSession(username)
    ensureUndergradPortal(username, session)
    val response = session.getTerms()
    val body = response.bodyAsText()

    if (isByxtSessionExpired(response, body)) {
      sessionManager.invalidateSession(username)
      throw LoginException("BYXT session expired")
    }
    if (response.status != HttpStatusCode.OK) throw ScheduleException("Fetch terms failed")

    val termResponse =
        try {
          json.decodeFromString<TermResponse>(body)
        } catch (_: Exception) {
          throw ScheduleException("Parse failed")
        }
    if (termResponse.code != "0") throw ScheduleException("Error: ${termResponse.msg}")

    return termResponse.datas
  }

  /** 获取指定学期的周次划分。 */
  suspend fun fetchWeeks(username: String, termCode: String): List<Week> {
    val session = sessionManager.requireSession(username)
    ensureUndergradPortal(username, session)
    val response = session.getWeeks(termCode)
    val body = response.bodyAsText()

    if (isByxtSessionExpired(response, body)) {
      sessionManager.invalidateSession(username)
      throw LoginException("BYXT session expired")
    }
    if (response.status != HttpStatusCode.OK) throw ScheduleException("Fetch weeks failed")
    val weekResponse =
        try {
          json.decodeFromString<WeekResponse>(body)
        } catch (_: Exception) {
          throw ScheduleException("Parse failed")
        }

    return weekResponse.datas
  }

  /** 获取周课表详情。 */
  suspend fun fetchWeeklySchedule(username: String, termCode: String, week: Int): WeeklySchedule {
    val session = sessionManager.requireSession(username)
    ensureUndergradPortal(username, session)
    val response = session.getWeeklySchedule(termCode, week)
    val body = response.bodyAsText()

    if (isByxtSessionExpired(response, body)) {
      sessionManager.invalidateSession(username)
      throw LoginException("BYXT session expired")
    }
    if (response.status != HttpStatusCode.OK) throw ScheduleException("Fetch schedule failed")
    val scheduleResponse =
        try {
          json.decodeFromString<WeeklyScheduleResponse>(body)
        } catch (_: Exception) {
          throw ScheduleException("Parse failed")
        }

    return scheduleResponse.datas
  }

  /** 获取今日排课摘要。 */
  suspend fun fetchTodaySchedule(username: String): List<TodayClass> {
    val session = sessionManager.requireSession(username)
    ensureUndergradPortal(username, session)
    val today = LocalDate.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd"))
    val response = session.getTodaySchedule(today)
    val body = response.bodyAsText()

    if (isByxtSessionExpired(response, body)) {
      sessionManager.invalidateSession(username)
      throw LoginException("BYXT session expired")
    }
    if (response.status != HttpStatusCode.OK) throw ScheduleException("Fetch today schedule failed")
    val todayResponse =
        try {
          json.decodeFromString<TodayScheduleResponse>(body)
        } catch (_: Exception) {
          throw ScheduleException("Parse failed")
        }

    return todayResponse.datas
  }

  private suspend fun SessionManager.UserSession.getTerms(): HttpResponse {
    return client.get(
        VpnCipher.toVpnUrl(
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do"
        )
    ) {
      applyScheduleHeaders()
    }
  }

  private suspend fun SessionManager.UserSession.getWeeks(termCode: String): HttpResponse {
    return client.get(
        VpnCipher.toVpnUrl(
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getTermWeeks.do?termCode=$termCode"
        )
    ) {
      applyScheduleHeaders()
    }
  }

  private suspend fun SessionManager.UserSession.getWeeklySchedule(
      termCode: String,
      week: Int,
  ): HttpResponse {
    return client.post(
        VpnCipher.toVpnUrl(
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
  }

  private suspend fun SessionManager.UserSession.getTodaySchedule(date: String): HttpResponse {
    return client.get(
        VpnCipher.toVpnUrl(
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/teachingSchedule/detail.do?rq=${date}&lxdm=student"
        )
    ) {
      applyScheduleHeaders()
    }
  }

  private fun isByxtSessionExpired(response: HttpResponse, body: String): Boolean =
      response.status == HttpStatusCode.Unauthorized ||
          !ByxtService.isSessionReady(response.status, response.request.url.toString(), body)

  private suspend fun ensureUndergradPortal(
      username: String,
      session: SessionManager.UserSession,
  ) {
    when (session.portalType) {
      AcademicPortalType.UNDERGRAD -> return
      AcademicPortalType.GRADUATE ->
          throw UnsupportedAcademicPortalException("研究生账号暂不支持当前本科教务接口")
      AcademicPortalType.UNKNOWN -> {
        when (val result = ByxtService.initializeSession(session.client)) {
          AcademicPortalProbeResult.UNDERGRAD_READY -> {
            sessionManager.updateSessionPortalType(username, AcademicPortalType.UNDERGRAD)
            return
          }
          AcademicPortalProbeResult.GRADUATE_READY -> {
            sessionManager.updateSessionPortalType(username, AcademicPortalType.GRADUATE)
            throw UnsupportedAcademicPortalException("研究生账号暂不支持当前本科教务接口")
          }
          AcademicPortalProbeResult.SSO_REQUIRED -> {
            sessionManager.invalidateSession(username)
            throw LoginException("BYXT session expired")
          }
          AcademicPortalProbeResult.UNAVAILABLE -> throw ScheduleException("BYXT service unavailable")
        }
      }
    }
  }
}

class ScheduleException(message: String) : Exception(message)
