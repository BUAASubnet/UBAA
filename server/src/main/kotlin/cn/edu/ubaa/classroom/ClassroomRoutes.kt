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
