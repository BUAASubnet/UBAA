package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.BuaaScoreResponse
import cn.edu.ubaa.model.dto.BuaaScoreTerm
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.parseBuaaScoreTermCode
import cn.edu.ubaa.model.dto.toGrade
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
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

internal class LocalGradeApiBackend : GradeApiBackend {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun getGrades(termCode: String): Result<GradeData> {
    if (LocalAuthSessionStore.get() == null) {
      return Result.failure(localUnauthenticatedApiException())
    }
    return try {
      val term = parseBuaaScoreTermCode(termCode)
      val client = LocalUpstreamClientProvider.shared()
      val activationResponse =
          client.get(localUpstreamUrl(BUAA_SCORE_URL)) { applyGradePageHeaders() }
      val activationBody = activationResponse.bodyAsText()
      if (isLocalScoreSessionExpired(activationResponse, activationBody)) {
        return Result.failure(resolveLocalBusinessAuthenticationFailure("grade_error"))
      }
      if (activationResponse.status != HttpStatusCode.OK) {
        return Result.failure(
            localBusinessApiException(
                "grade_error",
                "成绩查询失败，请稍后重试",
                activationResponse.status,
            )
        )
      }

      val response =
          client.post(localUpstreamUrl(BUAA_SCORE_URL)) {
            applyGradeQueryHeaders()
            setBody(gradeFormBody(term))
          }
      parseGrades(termCode, response)
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("成绩查询失败，请稍后重试"))
    }
  }

  private fun HttpRequestBuilder.applyGradePageHeaders() {
    header(
        HttpHeaders.Accept,
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    )
  }

  private fun HttpRequestBuilder.applyGradeQueryHeaders() {
    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
    header("X-Requested-With", "XMLHttpRequest")
    header(HttpHeaders.Referrer, localUpstreamUrl(BUAA_SCORE_URL))
  }

  private fun gradeFormBody(term: BuaaScoreTerm): FormDataContent =
      FormDataContent(
          Parameters.build {
            append("xq", term.semester.toString())
            append("year", term.year)
          }
      )

  private suspend fun parseGrades(termCode: String, response: HttpResponse): Result<GradeData> {
    return try {
      val body = response.bodyAsText()
      if (isLocalScoreSessionExpired(response, body)) {
        return Result.failure(resolveLocalBusinessAuthenticationFailure("grade_error"))
      }
      if (response.status != HttpStatusCode.OK) {
        return Result.failure(
            localBusinessApiException("grade_error", "成绩查询失败，请稍后重试", response.status)
        )
      }

      val payload = json.decodeFromString<BuaaScoreResponse>(body)
      if (payload.code != 0) {
        Result.failure(localBusinessApiException("grade_error", "成绩查询失败，请稍后重试"))
      } else {
        Result.success(
            GradeData(
                termCode = termCode,
                grades = payload.data.values.map { it.toGrade(termCode) },
            )
        )
      }
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("成绩查询失败，请稍后重试"))
    }
  }

  private fun isLocalScoreSessionExpired(response: HttpResponse, body: String): Boolean {
    if (response.status == HttpStatusCode.Unauthorized) return true
    if (localIsSsoUrl(response.call.request.url.toString())) return true
    return body.contains("input name=\"execution\"", ignoreCase = true) ||
        body.contains("统一身份认证", ignoreCase = true)
  }

  private companion object {
    const val BUAA_SCORE_URL = "https://app.buaa.edu.cn/buaascore/wap/default/index"
  }
}
