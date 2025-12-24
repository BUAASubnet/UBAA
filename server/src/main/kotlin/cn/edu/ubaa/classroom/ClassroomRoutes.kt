package cn.edu.ubaa.classroom

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.classroomRouting() {
    route("/api/v1/classroom") {
        get("/query") {
            val username = call.jwtUsername ?: return@get call.respond(HttpStatusCode.Unauthorized)
            val xqid = call.parameters["xqid"]?.toIntOrNull() ?: 1
            val date = call.parameters["date"] ?: ""
            application.log.info(
                    "Classroom query request from user: {}, xqid: {}, date: {}",
                    username,
                    xqid,
                    date
            )

            if (date.isEmpty()) {
                application.log.warn("Classroom query failed: date is missing")
                return@get call.respond(HttpStatusCode.BadRequest, "Date is required")
            }

            try {
                val client = ClassroomClient(username)
                val result = client.query(xqid, date)
                application.log.info("Classroom query successful for user: {}", username)
                call.respond(HttpStatusCode.OK, result)
            } catch (e: Exception) {
                application.log.error("Classroom query failed for user: {}", username, e)
                call.respond(
                        HttpStatusCode.InternalServerError,
                        ErrorResponse(
                                ErrorDetails(
                                        "classroom_query_failed",
                                        e.message ?: "Failed to query classrooms"
                                )
                        )
                )
            }
        }
    }
}
