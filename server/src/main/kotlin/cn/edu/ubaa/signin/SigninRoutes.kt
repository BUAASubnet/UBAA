package cn.edu.ubaa.signin

import cn.edu.ubaa.auth.JwtAuth.requireUserSession
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.signinRouting() {
    route("/api/v1/signin") {
        get("/today") {
            val session = call.requireUserSession()
            val studentId = session.userData.schoolid
            val response = SigninService.getTodayClasses(studentId)
            call.respond(response)
        }

        post("/do") {
            val session = call.requireUserSession()
            val studentId = session.userData.schoolid
            val courseId =
                    call.parameters["courseId"]
                            ?: return@post call.respondText(
                                    "Missing courseId",
                                    status = io.ktor.http.HttpStatusCode.BadRequest
                            )
            val response = SigninService.performSignin(studentId, courseId)
            call.respond(response)
        }
    }
}
