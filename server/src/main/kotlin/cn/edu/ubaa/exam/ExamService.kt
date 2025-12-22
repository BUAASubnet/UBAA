package cn.edu.ubaa.exam

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.utils.VpnCipher
import cn.edu.ubaa.model.dto.ExamArrangementData
import cn.edu.ubaa.model.dto.ExamResponse
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

class ExamService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val json: Json = Json { ignoreUnknownKeys = true }
) {
    private val log = LoggerFactory.getLogger(ExamService::class.java)

    private fun HttpRequestBuilder.applyExamHeaders() {
        header(HttpHeaders.Accept, "*/*")
        header("X-Requested-With", "XMLHttpRequest")
        header(HttpHeaders.Referrer, VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/home/index.html"))
    }

    suspend fun getExamArrangement(username: String, termCode: String): ExamArrangementData {
        log.info("Fetching exams via homeapp for username: {}, termCode: {}", username, termCode)
        val session = sessionManager.requireSession(username)

        val response = session.getExams(termCode)
        val body = response.bodyAsText()
        log.debug("Exams response status: {}", response.status)
        log.debug("Exams response body (truncated): {}", body.take(200))

        if (response.status != HttpStatusCode.OK) {
            throw ExamException("Failed to fetch exams. Status: ${response.status}")
        }

        val examResponse = runCatching {
            json.decodeFromString<ExamResponse>(body)
        }.getOrElse { throwable ->
            log.error("Failed to parse exams response for username: {}", username, throwable)
            throw ExamException("Failed to parse exams response.")
        }

        if (examResponse.code != "0") {
             throw ExamException("Failed to retrieve exams. Code: ${examResponse.code}, Message: ${examResponse.msg}")
        }

        // 将扁平列表映射为客户端期望的结构（全部放入 arranged 列表）
        return ExamArrangementData(
            arranged = examResponse.datas
        )
    }

    private suspend fun SessionManager.UserSession.getExams(termCode: String): HttpResponse {
        return try {
            val url = VpnCipher.toVpnUrl("https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do?termCode=$termCode")
            client.get(url) {
                applyExamHeaders()
            }
        } catch (e: Exception) {
            log.error("Error while calling exams endpoint for username: {}", username, e)
            throw ExamException("Failed to call exams endpoint.")
        }
    }
}

class ExamException(message: String) : Exception(message)
