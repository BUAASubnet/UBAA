package cn.edu.ubaa.signin

import cn.edu.ubaa.auth.JwtAuth.requireUserSession
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/** 注册课堂签到相关路由。 */
fun Route.signinRouting() {
  route("/api/v1/signin") {
    /** GET /api/v1/signin/today 获取今日可签到的课堂列表。 */
    get("/today") {
      val session = call.requireUserSession()
      call.respond(SigninService.getTodayClasses(session.userData.schoolid))
    }

    /** POST /api/v1/signin/do 执行签到。 @param courseId 课堂排课 ID。 */
    post("/do") {
      val session = call.requireUserSession()
      val courseId =
        call.parameters["courseId"]
          ?: return@post call.respond(io.ktor.http.HttpStatusCode.BadRequest)
      call.respond(SigninService.performSignin(session.userData.schoolid, courseId))
    }
  }
}
