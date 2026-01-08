package cn.edu.ubaa.schedule

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/** 注册课表查询相关路由。 */
fun Route.scheduleRouting() {
  val scheduleService = ScheduleService()
  route("/api/v1/schedule") {
    /** GET /api/v1/schedule/terms 获取可用学期列表。 */
    get("/terms") {
      val username = call.jwtUsername!!
      try {
        val terms = scheduleService.fetchTerms(username)
        call.respond(HttpStatusCode.OK, terms)
      } catch (e: Exception) {
        val status =
          if (e is LoginException) HttpStatusCode.Unauthorized else HttpStatusCode.BadGateway
        call.respond(status, ErrorResponse(ErrorDetails("error", e.message ?: "Error")))
      }
    }

    /** GET /api/v1/schedule/weeks 获取指定学期的教学周列表。 */
    get("/weeks") {
      val username = call.jwtUsername!!
      val termCode =
        call.request.queryParameters["termCode"]
          ?: return@get call.respond(HttpStatusCode.BadRequest)
      try {
        val weeks = scheduleService.fetchWeeks(username, termCode)
        call.respond(HttpStatusCode.OK, weeks)
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.BadGateway,
          ErrorResponse(ErrorDetails("error", e.message ?: "Error")),
        )
      }
    }

    /** GET /api/v1/schedule/week 获取指定周次的课程表详细排课。 */
    get("/week") {
      val username = call.jwtUsername!!
      val termCode =
        call.request.queryParameters["termCode"]
          ?: return@get call.respond(HttpStatusCode.BadRequest)
      val week =
        call.request.queryParameters["week"]?.toIntOrNull()
          ?: return@get call.respond(HttpStatusCode.BadRequest)
      try {
        val schedule = scheduleService.fetchWeeklySchedule(username, termCode, week)
        call.respond(HttpStatusCode.OK, schedule)
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.BadGateway,
          ErrorResponse(ErrorDetails("error", e.message ?: "Error")),
        )
      }
    }

    /** GET /api/v1/schedule/today 获取今日课程安排摘要。 */
    get("/today") {
      val username = call.jwtUsername!!
      try {
        val todaySchedule = scheduleService.fetchTodaySchedule(username)
        call.respond(HttpStatusCode.OK, todaySchedule)
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.BadGateway,
          ErrorResponse(ErrorDetails("error", e.message ?: "Error")),
        )
      }
    }
  }
}
