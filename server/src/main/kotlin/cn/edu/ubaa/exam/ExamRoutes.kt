package cn.edu.ubaa.exam

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.examRouting() {
    val examService = ExamService()

    route("/api/v1/exam") {
        get("/list") {
            val username = call.jwtUsername!!
            val termCode = call.request.queryParameters["termCode"]
            application.log.info(
                    "Exam list request from user: {}, termCode: {}",
                    username,
                    termCode
            )

            if (termCode.isNullOrBlank()) {
                application.log.warn("Exam list request failed: termCode is missing")
                call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                                ErrorDetails("invalid_request", "termCode parameter is required")
                        )
                )
                return@get
            }

            try {
                val examData = examService.getExamArrangement(username, termCode)
                application.log.info("Exam list fetched successfully for user: {}", username)
                call.respond(HttpStatusCode.OK, examData)
            } catch (e: LoginException) {
                application.log.warn("Exam list fetch failed for user {}: {}", username, e.message)
                call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                                ErrorDetails(
                                        "unauthenticated",
                                        e.message ?: "Session is not available."
                                )
                        )
                )
            } catch (e: ExamException) {
                call.respond(
                        HttpStatusCode.BadGateway,
                        ErrorResponse(
                                ErrorDetails(
                                        "upstream_error",
                                        e.message ?: "Failed to fetch exam data."
                                )
                        )
                )
            } catch (e: Exception) {
                call.application.environment.log.error(
                        "Unexpected error while fetching exam list.",
                        e
                )
                call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                                ErrorDetails(
                                        "internal_server_error",
                                        "An unexpected server error occurred."
                                )
                        )
                )
            }
        }
    }
}
