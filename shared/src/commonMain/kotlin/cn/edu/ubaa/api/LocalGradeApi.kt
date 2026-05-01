package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.GradeResponse
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
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

internal class LocalGradeApiBackend : GradeApiBackend {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun getGrades(termCode: String): Result<GradeData> =
      withLocalUndergradPortalAccess(
          unsupportedMessage = "研究生账号暂不支持当前本科成绩接口",
          unavailableCode = "grade_error",
      ) {
        val response =
            LocalUpstreamClientProvider.shared().post(
                localUpstreamUrl(
                    "https://byxt.buaa.edu.cn/jwapp/sys/cjzhcxapp/modules/wdcj/cxwdcj.do"
                )
            ) {
              applyGradeHeaders()
              setBody(gradeFormBody())
            }
        parseGrades(termCode, response)
      }

  private fun HttpRequestBuilder.applyGradeHeaders() {
    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
    header("X-Requested-With", "XMLHttpRequest")
    header(
        HttpHeaders.Referrer,
        localUpstreamUrl("https://byxt.buaa.edu.cn/jwapp/sys/cjzhcxapp/*default/index.do"),
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

  private suspend fun parseGrades(termCode: String, response: HttpResponse): Result<GradeData> {
    return try {
      val body = response.bodyAsText()
      if (isLocalByxtSessionExpired(response, body)) {
        return Result.failure(resolveLocalBusinessAuthenticationFailure("grade_error"))
      }
      if (response.status != HttpStatusCode.OK) {
        return Result.failure(
            localBusinessApiException("grade_error", "成绩查询失败，请稍后重试", response.status)
        )
      }

      val payload = json.decodeFromString<GradeResponse>(body)
      if (payload.code != "0") {
        Result.failure(localBusinessApiException("grade_error", "成绩查询失败，请稍后重试"))
      } else {
        Result.success(
            GradeData(
                termCode = termCode,
                grades = payload.datas.cxwdcj.rows.filter { it.termCode == termCode },
            )
        )
      }
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("成绩查询失败，请稍后重试"))
    }
  }
}
