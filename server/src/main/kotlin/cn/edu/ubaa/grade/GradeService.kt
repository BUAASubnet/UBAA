package cn.edu.ubaa.grade

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.auth.ensureUndergradPortalAccess
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.GradeResponse
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/** 成绩查询业务服务。负责从教务系统 (BYXT) 抓取并解析成绩数据。 */
class GradeService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
  private val log = LoggerFactory.getLogger(GradeService::class.java)

  private fun HttpRequestBuilder.applyGradeHeaders() {
    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
    header("X-Requested-With", "XMLHttpRequest")
    header(
        HttpHeaders.Referrer,
        VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/cjzhcxapp/*default/index.do"),
    )
  }

  private fun gradeFormBody(): FormDataContent =
      FormDataContent(
          Parameters.build {
            append("pageSize", "5000")
            append("pageNumber", "1")
            append("*order", "-XNXQDM,KCH")
          }
      )

  suspend fun getGrades(username: String, termCode: String): GradeData {
    val session = sessionManager.requireSession(username)
    ensureUndergradPortalAccess(
        sessionManager = sessionManager,
        username = username,
        session = session,
        graduateUnsupportedMessage = "研究生账号暂不支持当前本科成绩接口",
        unavailableExceptionFactory = { GradeException("BYXT service unavailable") },
    )

    val response = session.getGrades(termCode)
    val body = response.bodyAsText()
    if (response.status != HttpStatusCode.OK)
        throw GradeException("Fetch failed: ${response.status}")

    val gradeResponse =
        try {
          json.decodeFromString<GradeResponse>(body)
        } catch (_: Exception) {
          throw GradeException("Parse failed")
        }

    if (gradeResponse.code != "0") throw GradeException("Business error: ${gradeResponse.msg}")

    return GradeData(
        termCode = termCode,
        grades = gradeResponse.datas.cxwdcj.rows.filter { it.termCode == termCode },
    )
  }

  private suspend fun SessionManager.UserSession.getGrades(termCode: String): HttpResponse {
    return AppObservability.observeUpstreamRequest("byxt", "list_grades") {
      client.post(
          VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/cjzhcxapp/modules/wdcj/cxwdcj.do")
      ) {
        applyGradeHeaders()
        setBody(gradeFormBody())
      }
    }
  }
}

class GradeException(message: String) : Exception(message)
