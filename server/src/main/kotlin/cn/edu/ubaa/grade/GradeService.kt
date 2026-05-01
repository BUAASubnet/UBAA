package cn.edu.ubaa.grade

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.BuaaScoreResponse
import cn.edu.ubaa.model.dto.BuaaScoreTerm
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.parseBuaaScoreTermCode
import cn.edu.ubaa.model.dto.toGrade
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import kotlinx.serialization.json.Json

/** 成绩查询业务服务。负责从北航成绩应用抓取并解析成绩数据。 */
class GradeService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
  private fun HttpRequestBuilder.applyGradePageHeaders() {
    header(
        HttpHeaders.Accept,
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    )
  }

  private fun HttpRequestBuilder.applyGradeQueryHeaders() {
    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
    header("X-Requested-With", "XMLHttpRequest")
    header(HttpHeaders.Referrer, VpnCipher.toVpnUrl(BUAA_SCORE_URL))
  }

  private fun gradeFormBody(term: BuaaScoreTerm): FormDataContent =
      FormDataContent(
          Parameters.build {
            append("xq", term.semester.toString())
            append("year", term.year)
          }
      )

  suspend fun getGrades(username: String, termCode: String): GradeData {
    val session = sessionManager.requireSession(username)
    val term = parseBuaaScoreTermCode(termCode)

    val activationResponse = session.activateGradeService()
    val activationBody = activationResponse.bodyAsText()
    if (isScoreSessionExpired(activationResponse, activationBody)) {
      throw LoginException("session expired")
    }
    if (activationResponse.status != HttpStatusCode.OK) {
      throw GradeException("Activate failed: ${activationResponse.status}")
    }

    val response = session.getGrades(term)
    val body = response.bodyAsText()
    if (isScoreSessionExpired(response, body)) {
      throw LoginException("session expired")
    }
    if (response.status != HttpStatusCode.OK) {
      throw GradeException("Fetch failed: ${response.status}")
    }

    val gradeResponse =
        try {
          json.decodeFromString<BuaaScoreResponse>(body)
        } catch (_: Exception) {
          throw GradeException("Parse failed")
        }

    if (gradeResponse.code != 0) throw GradeException("Business error: ${gradeResponse.message}")

    return GradeData(
        termCode = termCode,
        grades = gradeResponse.data.values.map { it.toGrade(termCode) },
    )
  }

  private suspend fun SessionManager.UserSession.activateGradeService(): HttpResponse {
    return AppObservability.observeUpstreamRequest("buaa_score", "activate_grade_service") {
      client.get(VpnCipher.toVpnUrl(BUAA_SCORE_URL)) { applyGradePageHeaders() }
    }
  }

  private suspend fun SessionManager.UserSession.getGrades(term: BuaaScoreTerm): HttpResponse {
    return AppObservability.observeUpstreamRequest("buaa_score", "list_grades") {
      client.post(VpnCipher.toVpnUrl(BUAA_SCORE_URL)) {
        applyGradeQueryHeaders()
        setBody(gradeFormBody(term))
      }
    }
  }

  private fun isScoreSessionExpired(response: HttpResponse, body: String): Boolean {
    if (response.status == HttpStatusCode.Unauthorized) return true
    val finalUrl = response.call.request.url.toString()
    if (finalUrl.contains("sso.buaa.edu.cn", ignoreCase = true)) return true
    if (
        finalUrl.contains("d.buaa.edu.cn", ignoreCase = true) &&
            finalUrl.contains("/login", ignoreCase = true)
    ) {
      return true
    }
    return body.contains("input name=\"execution\"", ignoreCase = true) ||
        body.contains("统一身份认证", ignoreCase = true)
  }

  private companion object {
    const val BUAA_SCORE_URL = "https://app.buaa.edu.cn/buaascore/wap/default/index"
  }
}

class GradeException(message: String) : Exception(message)
