package cn.edu.ubaa.exam

import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.UnsupportedAcademicPortalException
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/** 注册考试安排查询路由。 */
fun Route.examRouting() {
  val examService = ExamService()

  route("/api/v1/exam") {
    /**
     * GET /api/v1/exam/list 获取当前用户的考试安排列表。
     *
     * @param termCode 学期代码。
     */
    get("/list") {
      val username = call.jwtUsername!!
      val termCode = call.request.queryParameters["termCode"]

      if (termCode.isNullOrBlank()) {
        return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      }

      call.observeBusinessOperation("exam", "list_exams") {
        try {
          val examData = examService.getExamArrangement(username, termCode)
          call.respond(HttpStatusCode.OK, examData)
        } catch (e: Exception) {
          when (e) {
            is LoginException -> markUnauthenticated()
            is UnsupportedAcademicPortalException -> markBusinessFailure()
            else -> markError()
          }
          val (status, code) = examErrorResponse(e)
          call.respondError(status, code)
        }
      }
    }
  }
}

internal fun examErrorResponse(error: Exception): Pair<HttpStatusCode, String> {
  return when (error) {
    is LoginException -> HttpStatusCode.Unauthorized to "invalid_token"
    is UnsupportedAcademicPortalException -> HttpStatusCode.NotImplemented to "unsupported_portal"
    else -> HttpStatusCode.BadGateway to "exam_error"
  }
}
