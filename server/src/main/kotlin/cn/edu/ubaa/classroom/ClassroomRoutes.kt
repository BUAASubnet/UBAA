package cn.edu.ubaa.classroom

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/**
 * 注册教室查询相关路由。
 */
fun Route.classroomRouting() {
    route("/api/v1/classroom") {
        /**
         * GET /api/v1/classroom/query
         * 查询空闲教室列表。
         * @param xqid 校区 ID（默认 1: 学院路）。
         * @param date 查询日期（yyyy-MM-dd）。
         */
        get("/query") {
            val username = call.jwtUsername ?: return@get call.respond(HttpStatusCode.Unauthorized)
            val xqid = call.parameters["xqid"]?.toIntOrNull() ?: 1
            val date = call.parameters["date"] ?: ""

            if (date.isEmpty()) {
                return@get call.respond(HttpStatusCode.BadRequest, "Date is required")
            }

            try {
                val client = ClassroomClient(username)
                val result = client.query(xqid, date)
                call.respond(HttpStatusCode.OK, result)
            } catch (e: Exception) {
                call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(ErrorDetails("classroom_query_failed", e.message ?: "Error"))
                )
            }
        }
    }
}