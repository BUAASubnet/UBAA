package cn.edu.ubaa.schedule

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.scheduleRouting() {
    val scheduleService = ScheduleService()
    route("/api/v1/schedule") {
        get("/terms") {
            val username = call.jwtUsername!!

            try {
                val terms = scheduleService.fetchTerms(username)
                call.respond(HttpStatusCode.OK, terms)
            } catch (e: LoginException) {
                call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                                ErrorDetails(
                                        "unauthenticated",
                                        e.message ?: "Session is not available."
                                )
                        )
                )
            } catch (e: ScheduleException) {
                call.respond(
                        HttpStatusCode.BadGateway,
                        ErrorResponse(
                                ErrorDetails(
                                        "upstream_error",
                                        e.message ?: "Failed to fetch schedule data."
                                )
                        )
                )
            } catch (e: Exception) {
                call.application.environment.log.error("Unexpected error while fetching terms.", e)
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

        get("/weeks") {
            val username = call.jwtUsername!!

            val termCode = call.request.queryParameters["termCode"]
            if (termCode.isNullOrBlank()) {
                call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                                ErrorDetails("invalid_request", "termCode parameter is required")
                        )
                )
                return@get
            }

            try {
                val weeks = scheduleService.fetchWeeks(username, termCode)
                call.respond(HttpStatusCode.OK, weeks)
            } catch (e: LoginException) {
                call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                                ErrorDetails(
                                        "unauthenticated",
                                        e.message ?: "Session is not available."
                                )
                        )
                )
            } catch (e: ScheduleException) {
                call.respond(
                        HttpStatusCode.BadGateway,
                        ErrorResponse(
                                ErrorDetails(
                                        "upstream_error",
                                        e.message ?: "Failed to fetch schedule data."
                                )
                        )
                )
            } catch (e: Exception) {
                call.application.environment.log.error("Unexpected error while fetching weeks.", e)
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

        get("/week") {
            val username = call.jwtUsername!!

            val termCode = call.request.queryParameters["termCode"]
            val weekStr = call.request.queryParameters["week"]

            if (termCode.isNullOrBlank()) {
                call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                                ErrorDetails("invalid_request", "termCode parameter is required")
                        )
                )
                return@get
            }

            if (weekStr.isNullOrBlank()) {
                call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(ErrorDetails("invalid_request", "week parameter is required"))
                )
                return@get
            }

            val week = weekStr.toIntOrNull()
            if (week == null || week <= 0) {
                call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                                ErrorDetails(
                                        "invalid_request",
                                        "week parameter must be a positive integer"
                                )
                        )
                )
                return@get
            }

            try {
                val schedule = scheduleService.fetchWeeklySchedule(username, termCode, week)
                call.respond(HttpStatusCode.OK, schedule)
            } catch (e: LoginException) {
                call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                                ErrorDetails(
                                        "unauthenticated",
                                        e.message ?: "Session is not available."
                                )
                        )
                )
            } catch (e: ScheduleException) {
                call.respond(
                        HttpStatusCode.BadGateway,
                        ErrorResponse(
                                ErrorDetails(
                                        "upstream_error",
                                        e.message ?: "Failed to fetch schedule data."
                                )
                        )
                )
            } catch (e: Exception) {
                call.application.environment.log.error(
                        "Unexpected error while fetching weekly schedule.",
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

        get("/today") {
            val username = call.jwtUsername!!

            try {
                val todaySchedule = scheduleService.fetchTodaySchedule(username)
                call.respond(HttpStatusCode.OK, todaySchedule)
            } catch (e: LoginException) {
                call.respond(
                        HttpStatusCode.Unauthorized,
                        ErrorResponse(
                                ErrorDetails(
                                        "unauthenticated",
                                        e.message ?: "Session is not available."
                                )
                        )
                )
            } catch (e: ScheduleException) {
                call.respond(
                        HttpStatusCode.BadGateway,
                        ErrorResponse(
                                ErrorDetails(
                                        "upstream_error",
                                        e.message ?: "Failed to fetch schedule data."
                                )
                        )
                )
            } catch (e: Exception) {
                call.application.environment.log.error(
                        "Unexpected error while fetching today's schedule.",
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
