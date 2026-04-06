package cn.edu.ubaa.classroom

import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/** 注册教室查询相关路由。 */
fun Route.classroomRouting() {
  route("/api/v1/classroom") {
    /**
     * GET /api/v1/classroom/query 查询空闲教室列表。
     *
     * @param xqid 校区 ID（默认 1: 学院路）。
     * @param date 查询日期（yyyy-MM-dd）。
     */
    get("/query") {
      val username =
          call.jwtUsername
              ?: return@get call.respondError(HttpStatusCode.Unauthorized, "invalid_token")
      val xqid = call.parameters["xqid"]?.toIntOrNull() ?: 1
      val date = call.parameters["date"] ?: ""

      if (date.isEmpty()) {
        return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      }

      call.observeBusinessOperation("classroom", "query") {
        try {
          val client = ClassroomClient(username)
          val result = client.query(xqid, date)
          call.respond(HttpStatusCode.OK, result)
        } catch (e: Exception) {
          markError()
          call.respondError(HttpStatusCode.InternalServerError, "classroom_query_failed")
        }
      }
    }
  }
}
