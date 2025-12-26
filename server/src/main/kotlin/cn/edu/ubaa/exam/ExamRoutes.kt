package cn.edu.ubaa.exam

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

/**
 * 注册考试安排查询路由。
 */
fun Route.examRouting() {
    val examService = ExamService()

    route("/api/v1/exam") {
        /**
         * GET /api/v1/exam/list
         * 获取当前用户的考试安排列表。
         * @param termCode 学期代码。
         */
        get("/list") {
            val username = call.jwtUsername!!
            val termCode = call.request.queryParameters["termCode"]

            if (termCode.isNullOrBlank()) {
                return@get call.respond(HttpStatusCode.BadRequest, ErrorResponse(ErrorDetails("invalid_request", "termCode is required")))
            }

            try {
                val examData = examService.getExamArrangement(username, termCode)
                call.respond(HttpStatusCode.OK, examData)
            } catch (e: Exception) {
                val status = if (e is LoginException) HttpStatusCode.Unauthorized else HttpStatusCode.BadGateway
                call.respond(status, ErrorResponse(ErrorDetails("error", e.message ?: "Error")))
            }
        }
    }
}