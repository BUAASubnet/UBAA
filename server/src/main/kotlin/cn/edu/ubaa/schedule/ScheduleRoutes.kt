package cn.edu.ubaa.schedule

import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.UnsupportedAcademicPortalException
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
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
      call.observeBusinessOperation("schedule", "list_terms") {
        try {
          val terms = scheduleService.fetchTerms(username)
          call.respond(HttpStatusCode.OK, terms)
        } catch (e: Exception) {
          markScheduleFailure(e)
          val (status, code) = scheduleErrorResponse(e)
          call.respondError(status, code)
        }
      }
    }

    /** GET /api/v1/schedule/weeks 获取指定学期的教学周列表。 */
    get("/weeks") {
      val username = call.jwtUsername!!
      val termCode =
          call.request.queryParameters["termCode"]
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      call.observeBusinessOperation("schedule", "list_weeks") {
        try {
          val weeks = scheduleService.fetchWeeks(username, termCode)
          call.respond(HttpStatusCode.OK, weeks)
        } catch (e: Exception) {
          markScheduleFailure(e)
          val (status, code) = scheduleErrorResponse(e)
          call.respondError(status, code)
        }
      }
    }

    /** GET /api/v1/schedule/week 获取指定周次的课程表详细排课。 */
    get("/week") {
      val username = call.jwtUsername!!
      val termCode =
          call.request.queryParameters["termCode"]
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      val week =
          call.request.queryParameters["week"]?.toIntOrNull()
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      call.observeBusinessOperation("schedule", "get_week") {
        try {
          val schedule = scheduleService.fetchWeeklySchedule(username, termCode, week)
          call.respond(HttpStatusCode.OK, schedule)
        } catch (e: Exception) {
          markScheduleFailure(e)
          val (status, code) = scheduleErrorResponse(e)
          call.respondError(status, code)
        }
      }
    }

    /** GET /api/v1/schedule/today 获取今日课程安排摘要。 */
    get("/today") {
      val username = call.jwtUsername!!
      call.observeBusinessOperation("schedule", "get_today") {
        try {
          val todaySchedule = scheduleService.fetchTodaySchedule(username)
          call.respond(HttpStatusCode.OK, todaySchedule)
        } catch (e: Exception) {
          markScheduleFailure(e)
          val (status, code) = scheduleErrorResponse(e)
          call.respondError(status, code)
        }
      }
    }
  }
}

private fun cn.edu.ubaa.metrics.BusinessOperationScope.markScheduleFailure(error: Exception) {
  when (error) {
    is LoginException -> markUnauthenticated()
    is UnsupportedAcademicPortalException -> markBusinessFailure()
    else -> markError()
  }
}

internal fun scheduleErrorResponse(error: Exception): Pair<HttpStatusCode, String> {
  return when (error) {
    is LoginException -> HttpStatusCode.Unauthorized to "invalid_token"
    is UnsupportedAcademicPortalException -> HttpStatusCode.NotImplemented to "unsupported_portal"
    else -> HttpStatusCode.BadGateway to "schedule_error"
  }
}
