package cn.edu.ubaa.bykc

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.model.dto.BykcCoursesResponse
import cn.edu.ubaa.model.dto.BykcSignRequest
import cn.edu.ubaa.model.dto.BykcSuccessResponse
import cn.edu.ubaa.model.dto.BykcUserProfileDto
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun Route.bykcRouting() {
        val bykcService = GlobalBykcService.instance

        route("/api/v1/bykc") {

                /** 获取博雅课程用户信息 */
                get("/profile") {
                        val username = call.jwtUsername!!

                        try {
                                val profile = bykcService.getUserProfile(username)
                                val profileDto =
                                        BykcUserProfileDto(
                                                id = profile.id,
                                                employeeId = profile.employeeId,
                                                realName = profile.realName,
                                                studentNo = profile.studentNo,
                                                studentType = profile.studentType,
                                                classCode = profile.classCode,
                                                collegeName = profile.college?.collegeName,
                                                termName = profile.term?.termName
                                        )
                                call.respond(HttpStatusCode.OK, profileDto)
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
                        } catch (e: BykcException) {
                                call.respond(
                                        HttpStatusCode.BadGateway,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "bykc_error",
                                                        e.message ?: "Failed to fetch BYKC profile."
                                                )
                                        )
                                )
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while fetching BYKC profile.",
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

                /**
                 * GET /api/v1/bykc/courses 获取博雅课程列表
                 *
                 * Query params:
                 * - page: 页码 (默认 1)
                 * - size: 每页数量 (默认 200)
                 * - all: 是否包含已过期课程 (默认 false)
                 */
                get("/courses") {
                        val username = call.jwtUsername!!

                        val page = call.request.queryParameters["page"]?.toIntOrNull() ?: 1
                        val size = call.request.queryParameters["size"]?.toIntOrNull() ?: 200
                        val includeAll = call.request.queryParameters["all"]?.toBoolean() ?: false

                        if (page < 1) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails("invalid_request", "page must be >= 1")
                                        )
                                )
                                return@get
                        }

                        if (size < 1 || size > 500) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "size must be between 1 and 500"
                                                )
                                        )
                                )
                                return@get
                        }

                        try {
                                val courses =
                                        if (includeAll) {
                                                bykcService.getAllCourses(username, page, size)
                                        } else {
                                                bykcService.getCourses(username, page, size)
                                        }

                                call.respond(
                                        HttpStatusCode.OK,
                                        BykcCoursesResponse(courses = courses, total = courses.size)
                                )
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
                        } catch (e: BykcException) {
                                call.respond(
                                        HttpStatusCode.BadGateway,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "bykc_error",
                                                        e.message ?: "Failed to fetch BYKC courses."
                                                )
                                        )
                                )
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while fetching BYKC courses.",
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

                /** GET /api/v1/bykc/statistics 获取课程统计信息 */
                get("/statistics") {
                        val username = call.jwtUsername!!

                        try {
                                val statistics = bykcService.getStatistics(username)
                                call.respond(HttpStatusCode.OK, statistics)
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
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while fetching BYKC statistics.",
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

                /** GET /api/v1/bykc/statistics 获取课程统计信息 */
                get("/statistics") {
                        val username = call.jwtUsername!!

                        try {
                                val statistics = bykcService.getStatistics(username)
                                call.respond(HttpStatusCode.OK, statistics)
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
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while fetching BYKC statistics.",
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

                /** POST /api/v1/bykc/courses/{courseId}/select 选择课程 */
                post("/courses/{courseId}/select") {
                        val username = call.jwtUsername!!

                        val courseIdStr = call.parameters["courseId"]
                        val courseId = courseIdStr?.toLongOrNull()

                        if (courseId == null) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "courseId must be a valid number"
                                                )
                                        )
                                )
                                return@post
                        }

                        try {
                                val result = bykcService.selectCourse(username, courseId)
                                result.fold(
                                        onSuccess = { message ->
                                                call.respond(
                                                        HttpStatusCode.OK,
                                                        BykcSuccessResponse(message)
                                                )
                                        },
                                        onFailure = { error ->
                                                when {
                                                        error.message?.contains("重复报名") == true -> {
                                                                call.respond(
                                                                        HttpStatusCode.Conflict,
                                                                        ErrorResponse(
                                                                                ErrorDetails(
                                                                                        "already_selected",
                                                                                        error.message
                                                                                                ?: "已报名过该课程"
                                                                                )
                                                                        )
                                                                )
                                                        }
                                                        error.message?.contains("人数已满") == true -> {
                                                                call.respond(
                                                                        HttpStatusCode.Conflict,
                                                                        ErrorResponse(
                                                                                ErrorDetails(
                                                                                        "course_full",
                                                                                        error.message
                                                                                                ?: "课程人数已满"
                                                                                )
                                                                        )
                                                                )
                                                        }
                                                        error.message?.contains("不可选择") == true -> {
                                                                call.respond(
                                                                        HttpStatusCode.Conflict,
                                                                        ErrorResponse(
                                                                                ErrorDetails(
                                                                                        "course_not_selectable",
                                                                                        error.message
                                                                                                ?: "该课程不可选择"
                                                                                )
                                                                        )
                                                                )
                                                        }
                                                        else -> {
                                                                call.respond(
                                                                        HttpStatusCode.BadGateway,
                                                                        ErrorResponse(
                                                                                ErrorDetails(
                                                                                        "select_failed",
                                                                                        error.message
                                                                                                ?: "选课失败"
                                                                                )
                                                                        )
                                                                )
                                                        }
                                                }
                                        }
                                )
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
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while selecting course.",
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

                /** DELETE /api/v1/bykc/courses/{courseId}/select 退选课程 */
                delete("/courses/{courseId}/select") {
                        val username = call.jwtUsername!!

                        val courseIdStr = call.parameters["courseId"]
                        val courseId = courseIdStr?.toLongOrNull()

                        if (courseId == null) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "courseId must be a valid number"
                                                )
                                        )
                                )
                                return@delete
                        }

                        try {
                                val result = bykcService.deselectCourse(username, courseId)
                                result.fold(
                                        onSuccess = { message ->
                                                call.respond(
                                                        HttpStatusCode.OK,
                                                        BykcSuccessResponse(message)
                                                )
                                        },
                                        onFailure = { error ->
                                                call.respond(
                                                        HttpStatusCode.BadRequest,
                                                        ErrorResponse(
                                                                ErrorDetails(
                                                                        "deselect_failed",
                                                                        error.message ?: "退选失败"
                                                                )
                                                        )
                                                )
                                        }
                                )
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
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while deselecting course.",
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

                /** GET /api/v1/bykc/courses/chosen 获取已选课程列表 */
                get("/courses/chosen") {
                        val username = call.jwtUsername!!

                        try {
                                val chosenCourses = bykcService.getChosenCourses(username)
                                call.respond(HttpStatusCode.OK, chosenCourses)
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
                        } catch (e: BykcException) {
                                call.respond(
                                        HttpStatusCode.BadGateway,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "bykc_error",
                                                        e.message
                                                                ?: "Failed to fetch chosen courses."
                                                )
                                        )
                                )
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while fetching chosen courses.",
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

                /** GET /api/v1/bykc/courses/{courseId} 获取课程详情 */
                get("/courses/{courseId}") {
                        val username = call.jwtUsername!!

                        val courseIdStr = call.parameters["courseId"]
                        val courseId = courseIdStr?.toLongOrNull()

                        if (courseId == null) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "courseId must be a valid number"
                                                )
                                        )
                                )
                                return@get
                        }

                        try {
                                val courseDetail = bykcService.getCourseDetail(username, courseId)
                                call.respond(HttpStatusCode.OK, courseDetail)
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
                        } catch (e: BykcException) {
                                call.respond(
                                        HttpStatusCode.BadGateway,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "bykc_error",
                                                        e.message
                                                                ?: "Failed to fetch course detail."
                                                )
                                        )
                                )
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while fetching course detail.",
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

                /** POST /api/v1/bykc/courses/{courseId}/sign 签到/签退 */
                post("/courses/{courseId}/sign") {
                        val username = call.jwtUsername!!

                        val courseIdStr = call.parameters["courseId"]
                        val courseId = courseIdStr?.toLongOrNull()

                        if (courseId == null) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "courseId must be a valid number"
                                                )
                                        )
                                )
                                return@post
                        }

                        val signRequest =
                                try {
                                        call.receive<BykcSignRequest>()
                                } catch (e: Exception) {
                                        call.respond(
                                                HttpStatusCode.BadRequest,
                                                ErrorResponse(
                                                        ErrorDetails(
                                                                "invalid_request",
                                                                "Invalid request body"
                                                        )
                                                )
                                        )
                                        return@post
                                }

                        if (signRequest.signType !in listOf(1, 2)) {
                                call.respond(
                                        HttpStatusCode.BadRequest,
                                        ErrorResponse(
                                                ErrorDetails(
                                                        "invalid_request",
                                                        "signType must be 1 (sign in) or 2 (sign out)"
                                                )
                                        )
                                )
                                return@post
                        }

                        try {
                                val result =
                                        if (signRequest.signType == 1) {
                                                bykcService.signIn(
                                                        username,
                                                        courseId,
                                                        signRequest.lat,
                                                        signRequest.lng
                                                )
                                        } else {
                                                bykcService.signOut(
                                                        username,
                                                        courseId,
                                                        signRequest.lat,
                                                        signRequest.lng
                                                )
                                        }

                                result.fold(
                                        onSuccess = { message ->
                                                call.respond(
                                                        HttpStatusCode.OK,
                                                        BykcSuccessResponse(message)
                                                )
                                        },
                                        onFailure = { error ->
                                                call.respond(
                                                        HttpStatusCode.BadRequest,
                                                        ErrorResponse(
                                                                ErrorDetails(
                                                                        "sign_failed",
                                                                        error.message ?: "签到/签退失败"
                                                                )
                                                        )
                                                )
                                        }
                                )
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
                        } catch (e: Exception) {
                                call.application.environment.log.error(
                                        "Unexpected error while signing course.",
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
