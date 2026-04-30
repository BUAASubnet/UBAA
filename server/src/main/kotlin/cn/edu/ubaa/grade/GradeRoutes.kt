package cn.edu.ubaa.grade

import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.UnsupportedAcademicPortalException
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/** 注册成绩查询路由。 */
fun Route.gradeRouting() {
  val gradeService = GradeService()

  route("/api/v1/grade") {
    get("/list") {
      val username = call.jwtUsername!!
      val termCode = call.request.queryParameters["termCode"]

      if (termCode.isNullOrBlank()) {
        return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      }

      call.observeBusinessOperation("grade", "list_grades") {
        try {
          val gradeData = gradeService.getGrades(username, termCode)
          call.respond(HttpStatusCode.OK, gradeData)
        } catch (e: Exception) {
          when (e) {
            is LoginException -> markUnauthenticated()
            is UnsupportedAcademicPortalException -> markBusinessFailure()
            else -> markError()
          }
          val (status, code) = gradeErrorResponse(e)
          call.respondError(status, code)
        }
      }
    }
  }
}

internal fun gradeErrorResponse(error: Exception): Pair<HttpStatusCode, String> {
  return when (error) {
    is LoginException -> HttpStatusCode.Unauthorized to "invalid_token"
    is UnsupportedAcademicPortalException -> HttpStatusCode.NotImplemented to "unsupported_portal"
    else -> HttpStatusCode.BadGateway to "grade_error"
  }
}
