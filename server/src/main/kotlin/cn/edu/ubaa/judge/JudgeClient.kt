package cn.edu.ubaa.judge

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.request.get
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpStatusCode
import org.slf4j.LoggerFactory

/** 希冀原始客户端。负责基于已登录的 SSO 会话访问 judge.buaa.edu.cn。 */
internal open class JudgeClient(
    private val username: String,
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
) {
  private val log = LoggerFactory.getLogger(JudgeClient::class.java)

  open suspend fun getCourses(): List<JudgeCourseRaw> {
    val body = getHtml("get_courses", "$BASE_URL/courselist.jsp?courseID=0")
    return JudgeParsers.parseCourses(body)
  }

  open suspend fun getAssignments(course: JudgeCourseRaw): List<JudgeAssignmentRaw> {
    selectCourse(course.courseId)
    val body = getHtml("get_assignments", "$BASE_URL/assignment/index.jsp")
    return JudgeParsers.parseAssignments(body, course)
  }

  open suspend fun getAssignmentDetail(
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
  ): JudgeAssignmentParsedDetail {
    selectCourse(courseId)
    val body = getHtml("get_assignment_detail", "$BASE_URL/assignment/index.jsp?assignID=$assignmentId")
    return JudgeParsers.parseAssignmentDetail(
        html = body,
        courseId = courseId,
        courseName = courseName,
        assignmentId = assignmentId,
        title = title,
    )
  }

  open fun close() = Unit

  private suspend fun selectCourse(courseId: String) {
    getHtml("select_course", "$BASE_URL/courselist.jsp?courseID=$courseId")
  }

  private suspend fun getHtml(operation: String, url: String): String {
    val session = sessionManager.requireSession(username)
    val response =
        AppObservability.observeUpstreamRequest("judge", operation) {
          session.client.get(normalizeUrl(url))
        }
    val body = response.bodyAsText()
    if (isSessionExpired(response, body)) {
      log.info("Judge auth expired for user {}", username)
      throw JudgeAuthenticationException("希冀登录状态异常，请重新登录后重试")
    }
    if (response.status != HttpStatusCode.OK) {
      throw JudgeException("希冀服务暂时不可用，请稍后重试")
    }
    return body
  }

  private fun isSessionExpired(response: HttpResponse, body: String): Boolean {
    if (response.status == HttpStatusCode.Unauthorized) return true
    val finalUrl = response.call.request.url.toString()
    if (finalUrl.contains("sso.buaa.edu.cn", ignoreCase = true)) return true
    val trimmed = body.trimStart()
    if (
        trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
            trimmed.startsWith("<html", ignoreCase = true)
    ) {
      return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
    }
    return false
  }

  private fun normalizeUrl(url: String): String = VpnCipher.toVpnUrl(url)

  companion object {
    private const val BASE_URL = "https://judge.buaa.edu.cn"
  }
}
