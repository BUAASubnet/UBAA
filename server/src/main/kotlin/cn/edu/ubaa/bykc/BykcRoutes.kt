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

/** 注册博雅课程 (BYKC) 相关路由。 包含用户信息、课程列表、统计信息、选课、退选及签到功能。 */
fun Route.bykcRouting() {
  val bykcService = GlobalBykcService.instance

  route("/api/v1/bykc") {

    /** GET /api/v1/bykc/profile 获取用户在博雅系统中的个人资料（如学号、学院、当前学期）。 */
    get("/profile") {
      val username = call.jwtUsername!!
      application.log.info("Fetching BYKC profile for user: {}", username)

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
            termName = profile.term?.termName,
          )
        call.respond(HttpStatusCode.OK, profileDto)
      } catch (e: LoginException) {
        call.respond(
          HttpStatusCode.Unauthorized,
          ErrorResponse(ErrorDetails("unauthenticated", e.message ?: "Session is not available.")),
        )
      } catch (e: BykcException) {
        call.respond(
          HttpStatusCode.BadGateway,
          ErrorResponse(ErrorDetails("bykc_error", e.message ?: "Failed to fetch BYKC profile.")),
        )
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(
            ErrorDetails("internal_server_error", "An unexpected server error occurred.")
          ),
        )
      }
    }

    /**
     * GET /api/v1/bykc/courses 获取博雅课程列表（支持分页和过滤）。
     *
     * @param page 页码（从 1 开始）。
     * @param size 每页数量。
     * @param all 是否包含已结束课程。
     */
    get("/courses") {
      val username = call.jwtUsername!!
      val page = call.request.queryParameters["page"]?.toIntOrNull() ?: 1
      val size = call.request.queryParameters["size"]?.toIntOrNull() ?: 20
      val includeAll = call.request.queryParameters["all"]?.toBoolean() ?: false

      if (page < 1 || size < 1 || size > 500) {
        call.respond(
          HttpStatusCode.BadRequest,
          ErrorResponse(ErrorDetails("invalid_request", "Invalid page or size")),
        )
        return@get
      }

      try {
        val coursePage =
          if (includeAll) bykcService.getAllCourses(username, page, size)
          else bykcService.getCourses(username, page, size)
        call.respond(
          HttpStatusCode.OK,
          BykcCoursesResponse(
            courses = coursePage.courses,
            total = coursePage.totalElements,
            totalPages = coursePage.totalPages,
            currentPage = coursePage.currentPage,
            pageSize = coursePage.pageSize,
          ),
        )
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_server_error", e.message ?: "Error")),
        )
      }
    }

    /** GET /api/v1/bykc/statistics 获取用户的博雅课程修读统计（有效次数及各分类达标情况）。 */
    get("/statistics") {
      val username = call.jwtUsername!!
      try {
        val statistics = bykcService.getStatistics(username)
        call.respond(HttpStatusCode.OK, statistics)
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_server_error", "Error")),
        )
      }
    }

    /** POST /api/v1/bykc/courses/{courseId}/select 选课（报名）。 */
    post("/courses/{courseId}/select") {
      val username = call.jwtUsername!!
      val courseId =
        call.parameters["courseId"]?.toLongOrNull()
          ?: return@post call.respond(HttpStatusCode.BadRequest)

      try {
        bykcService
          .selectCourse(username, courseId)
          .fold(
            onSuccess = { call.respond(HttpStatusCode.OK, BykcSuccessResponse(it)) },
            onFailure = { error ->
              val code =
                when {
                  error.message?.contains("重复报名") == true -> "already_selected"
                  error.message?.contains("人数已满") == true -> "course_full"
                  error.message?.contains("不可选择") == true -> "course_not_selectable"
                  else -> "select_failed"
                }
              call.respond(
                HttpStatusCode.Conflict,
                ErrorResponse(ErrorDetails(code, error.message ?: "Failed")),
              )
            },
          )
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_error", "Error")),
        )
      }
    }

    /** DELETE /api/v1/bykc/courses/{courseId}/select 退选（取消报名）。 */
    delete("/courses/{courseId}/select") {
      val username = call.jwtUsername!!
      val courseId =
        call.parameters["courseId"]?.toLongOrNull()
          ?: return@delete call.respond(HttpStatusCode.BadRequest)

      try {
        bykcService
          .deselectCourse(username, courseId)
          .fold(
            onSuccess = { call.respond(HttpStatusCode.OK, BykcSuccessResponse(it)) },
            onFailure = {
              call.respond(
                HttpStatusCode.BadRequest,
                ErrorResponse(ErrorDetails("deselect_failed", it.message ?: "Failed")),
              )
            },
          )
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_error", "Error")),
        )
      }
    }

    /** GET /api/v1/bykc/courses/chosen 获取当前用户已报名的博雅课程。 */
    get("/courses/chosen") {
      val username = call.jwtUsername!!
      try {
        val chosenCourses = bykcService.getChosenCourses(username)
        call.respond(HttpStatusCode.OK, chosenCourses)
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_error", "Error")),
        )
      }
    }

    /** GET /api/v1/bykc/courses/{courseId} 获取单门课程的详细信息。 */
    get("/courses/{courseId}") {
      val username = call.jwtUsername!!
      val courseId =
        call.parameters["courseId"]?.toLongOrNull()
          ?: return@get call.respond(HttpStatusCode.BadRequest)
      try {
        val courseDetail = bykcService.getCourseDetail(username, courseId)
        call.respond(HttpStatusCode.OK, courseDetail)
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_error", "Error")),
        )
      }
    }

    /** POST /api/v1/bykc/courses/{courseId}/sign 执行签到或签退操作。 */
    post("/courses/{courseId}/sign") {
      val username = call.jwtUsername!!
      val courseId =
        call.parameters["courseId"]?.toLongOrNull()
          ?: return@post call.respond(HttpStatusCode.BadRequest)
      val signRequest =
        try {
          call.receive<BykcSignRequest>()
        } catch (e: Exception) {
          return@post call.respond(
            HttpStatusCode.BadRequest,
            ErrorResponse(ErrorDetails("invalid_request", "Invalid body")),
          )
        }

      try {
        val result =
          if (signRequest.signType == 1) {
            bykcService.signIn(username, courseId, signRequest.lat, signRequest.lng)
          } else {
            bykcService.signOut(username, courseId, signRequest.lat, signRequest.lng)
          }

        result.fold(
          onSuccess = { call.respond(HttpStatusCode.OK, BykcSuccessResponse(it)) },
          onFailure = {
            call.respond(
              HttpStatusCode.BadRequest,
              ErrorResponse(ErrorDetails("sign_failed", it.message ?: "Failed")),
            )
          },
        )
      } catch (e: Exception) {
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_error", "Error")),
        )
      }
    }
  }
}
