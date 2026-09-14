package cn.edu.ubaa.schedule

import cn.edu.ubaa.api.feature.GraduateScheduleAuthenticationException
import cn.edu.ubaa.api.feature.fetchGraduateSchedule
import cn.edu.ubaa.auth.AcademicPortalProbeResult
import cn.edu.ubaa.auth.AcademicPortalType
import cn.edu.ubaa.auth.AcademicPortalWarmupCoordinator
import cn.edu.ubaa.auth.ByxtService
import cn.edu.ubaa.auth.GlobalAcademicPortalWarmupCoordinator
import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/** 课表业务服务。 负责与教务系统 (BYXT) 通信，获取学期、周次及排课数据。 */
class ScheduleService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val json: Json = Json { ignoreUnknownKeys = true },
    private val portalWarmupCoordinator: AcademicPortalWarmupCoordinator =
        GlobalAcademicPortalWarmupCoordinator.instance,
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
    session.graduateScheduleIfNeeded(username)?.let {
      return it.terms()
    }
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
    session.graduateScheduleIfNeeded(username, termCode)?.let {
      return it.weeks(termCode, graduateToday())
    }
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
    session.graduateScheduleIfNeeded(username, termCode)?.let {
      return it.weekly(termCode, week)
    }
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
    session.graduateScheduleIfNeeded(username)?.let {
      return it.today(graduateToday())
    }
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

  private fun graduateToday() =
      kotlinx.datetime.LocalDate.parse(
          LocalDate.now(java.time.ZoneId.of("Asia/Shanghai")).toString()
      )

  private suspend fun SessionManager.UserSession.graduateScheduleIfNeeded(
      username: String,
      termCode: String? = null,
  ): GraduateSchedule? {
    if (portalType == AcademicPortalType.UNDERGRAD) return null
    if (portalType == AcademicPortalType.UNKNOWN) {
      val probe =
          try {
            portalWarmupCoordinator.awaitOrStart(username, client)
          } catch (error: CancellationException) {
            throw error
          } catch (_: Exception) {
            AcademicPortalProbeResult.UNAVAILABLE
          }
      if (probe == AcademicPortalProbeResult.UNDERGRAD_READY) {
        sessionManager.updateSessionPortalType(username, AcademicPortalType.UNDERGRAD)
        return null
      }
    }
    // 门户探测不代表课表子应用的状态；保留主会话，由 GSMIS 课表接口验证访问权。
    return try {
      AppObservability.observeUpstreamRequest("gsmis", "get_schedule") {
            fetchGraduateSchedule(client, VpnCipher::toVpnUrl, termCode)
          }
          .also { sessionManager.updateSessionPortalType(username, AcademicPortalType.GRADUATE) }
    } catch (_: GraduateScheduleAuthenticationException) {
      throw LoginException("研究生课表会话已过期")
    }
  }

  private suspend fun SessionManager.UserSession.getTerms(): HttpResponse {
    return AppObservability.observeUpstreamRequest("byxt", "list_terms") {
      client.get(
          VpnCipher.toVpnUrl(
              "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do"
          )
      ) {
        applyScheduleHeaders()
      }
    }
  }

  private suspend fun SessionManager.UserSession.getWeeks(termCode: String): HttpResponse {
    return AppObservability.observeUpstreamRequest("byxt", "list_weeks") {
      client.get(
          VpnCipher.toVpnUrl(
              "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getTermWeeks.do?termCode=$termCode"
          )
      ) {
        applyScheduleHeaders()
      }
    }
  }

  private suspend fun SessionManager.UserSession.getWeeklySchedule(
      termCode: String,
      week: Int,
  ): HttpResponse {
    return AppObservability.observeUpstreamRequest("byxt", "get_week") {
      client.post(
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
  }

  private suspend fun SessionManager.UserSession.getTodaySchedule(date: String): HttpResponse {
    return AppObservability.observeUpstreamRequest("byxt", "get_today") {
      client.get(
          VpnCipher.toVpnUrl(
              "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/teachingSchedule/detail.do?rq=${date}&lxdm=student"
          )
      ) {
        applyScheduleHeaders()
      }
    }
  }

  private fun isByxtSessionExpired(response: HttpResponse, body: String): Boolean =
      response.status == HttpStatusCode.Unauthorized ||
          !ByxtService.isSessionReady(response.status, response.request.url.toString(), body)
}

class ScheduleException(message: String) : Exception(message)
