package cn.edu.ubaa.signin

import cn.edu.ubaa.auth.JwtAuth.requireUserSession
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/** 注册课堂签到相关路由。 */
fun Route.signinRouting() {
  route("/api/v1/signin") {
    /** GET /api/v1/signin/today 获取今日可签到的课堂列表。 */
    get("/today") {
      val session = call.requireUserSession()
      call.observeBusinessOperation("signin", "get_today") {
        try {
          call.respond(SigninService.getTodayClasses(session.userData.schoolid))
        } catch (e: Exception) {
          markError()
          call.respondError(HttpStatusCode.BadGateway, "signin_load_failed")
        }
      }
    }

    /** POST /api/v1/signin/do 执行签到。 @param courseId 课堂排课 ID。 */
    post("/do") {
      val session = call.requireUserSession()
      val courseId =
          call.parameters["courseId"]
              ?: return@post call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      call.observeBusinessOperation("signin", "sign_in") {
        try {
          val response = SigninService.performSignin(session.userData.schoolid, courseId)
          if (!response.success) {
            markBusinessFailure()
          }
          call.respond(response)
        } catch (e: Exception) {
          markError()
          call.respondError(HttpStatusCode.BadGateway, "signin_failed")
        }
      }
    }
  }
}
