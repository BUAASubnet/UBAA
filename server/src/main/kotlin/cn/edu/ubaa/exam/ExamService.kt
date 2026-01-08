package cn.edu.ubaa.exam

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.ExamArrangementData
import cn.edu.ubaa.model.dto.ExamResponse
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/** 考试安排业务服务。 负责从教务系统 (BYXT) 抓取并解析考试数据。 */
class ExamService(
  private val sessionManager: SessionManager = GlobalSessionManager.instance,
  private val json: Json = Json { ignoreUnknownKeys = true },
) {
  private val log = LoggerFactory.getLogger(ExamService::class.java)

  /** 设置教务系统所需的公共请求头。 */
  private fun HttpRequestBuilder.applyExamHeaders() {
    header(HttpHeaders.Accept, "*/*")
    header("X-Requested-With", "XMLHttpRequest")
    header(
      HttpHeaders.Referrer,
      VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/home/index.html"),
    )
  }

  /**
   * 获取指定学期的考试安排。
   *
   * @param username 用户名。
   * @param termCode 学期代码。
   * @return 包含考试列表的汇总数据。
   */
  suspend fun getExamArrangement(username: String, termCode: String): ExamArrangementData {
    val session = sessionManager.requireSession(username)
    val response = session.getExams(termCode)
    val body = response.bodyAsText()

    if (response.status != HttpStatusCode.OK)
      throw ExamException("Fetch failed: ${response.status}")

    val examResponse =
      try {
        json.decodeFromString<ExamResponse>(body)
      } catch (e: Exception) {
        throw ExamException("Parse failed")
      }

    if (examResponse.code != "0") throw ExamException("Business error: ${examResponse.msg}")

    return ExamArrangementData(arranged = examResponse.datas)
  }

  /** 执行具体的 HTTP 请求抓取考试数据。 */
  private suspend fun SessionManager.UserSession.getExams(termCode: String): HttpResponse {
    val url =
      VpnCipher.toVpnUrl(
        "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do?termCode=$termCode"
      )
    return client.get(url) { applyExamHeaders() }
  }
}

/** 考试模块自定义异常。 */
class ExamException(message: String) : Exception(message)
