package cn.edu.ubaa.bykc

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.BusinessOperationScope
import cn.edu.ubaa.metrics.observeBusinessOperation
import cn.edu.ubaa.model.dto.BykcCoursesResponse
import cn.edu.ubaa.model.dto.BykcSignRequest
import cn.edu.ubaa.model.dto.BykcSuccessResponse
import cn.edu.ubaa.model.dto.BykcUserProfileDto
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.application.ApplicationCall
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.coroutines.CancellationException

/** 注册博雅课程 (BYKC) 相关路由。 包含用户信息、课程列表、统计信息、选课、退选及签到功能。 */
fun Route.bykcRouting() {
  val bykcService = GlobalBykcService.instance

  route("/api/v1/bykc") {

    /** GET /api/v1/bykc/profile 获取用户在博雅系统中的个人资料（如学号、学院、当前学期）。 */
    get("/profile") {
      val username = call.jwtUsername!!
      application.log.info("Fetching BYKC profile for user: {}", username)

      call.observeBusinessOperation("bykc", "get_profile") {
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
        } catch (e: Exception) {
          call.respondBykcError(e, this)
        }
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
        call.respondError(HttpStatusCode.BadRequest, "invalid_request")
        return@get
      }

      call.observeBusinessOperation(
          "bykc",
          if (includeAll) "list_all_courses" else "list_courses",
      ) {
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
          call.respondBykcError(e, this)
        }
      }
    }

    /** GET /api/v1/bykc/statistics 获取用户的博雅课程修读统计（有效次数及各分类达标情况）。 */
    get("/statistics") {
      val username = call.jwtUsername!!
      call.observeBusinessOperation("bykc", "get_statistics") {
        try {
          val statistics = bykcService.getStatistics(username)
          call.respond(HttpStatusCode.OK, statistics)
        } catch (e: Exception) {
          call.respondBykcError(e, this)
        }
      }
    }

    /** POST /api/v1/bykc/courses/{courseId}/select 选课（报名）。 */
    post("/courses/{courseId}/select") {
      val username = call.jwtUsername!!
      val courseId =
          call.parameters["courseId"]?.toLongOrNull()
              ?: return@post call.respondError(HttpStatusCode.BadRequest, "invalid_request")

      call.observeBusinessOperation("bykc", "select_course") {
        try {
          bykcService
              .selectCourse(username, courseId)
              .fold(
                  onSuccess = { call.respond(HttpStatusCode.OK, BykcSuccessResponse(it)) },
                  onFailure = { error ->
                    markBusinessFailure()
                    val code =
                        when {
                          error.message?.contains("重复报名") == true -> "already_selected"
                          error.message?.contains("人数已满") == true -> "course_full"
                          error.message?.contains("不可选择") == true -> "course_not_selectable"
                          else -> "select_failed"
                        }
                    call.respond(
                        HttpStatusCode.Conflict,
                        ErrorResponse(ErrorDetails(code, cn.edu.ubaa.auth.userFacingMessage(code))),
                    )
                  },
              )
        } catch (e: Exception) {
          call.respondBykcError(e, this)
        }
      }
    }

    /** DELETE /api/v1/bykc/courses/{courseId}/select 退选（取消报名）。 */
    delete("/courses/{courseId}/select") {
      val username = call.jwtUsername!!
      val courseId =
          call.parameters["courseId"]?.toLongOrNull()
              ?: return@delete call.respondError(HttpStatusCode.BadRequest, "invalid_request")

      call.observeBusinessOperation("bykc", "deselect_course") {
        try {
          bykcService
              .deselectCourse(username, courseId)
              .fold(
                  onSuccess = { call.respond(HttpStatusCode.OK, BykcSuccessResponse(it)) },
                  onFailure = {
                    markBusinessFailure()
                    call.respond(
                        HttpStatusCode.BadRequest,
                        ErrorResponse(
                            ErrorDetails(
                                "deselect_failed",
                                cn.edu.ubaa.auth.userFacingMessage("deselect_failed"),
                            )
                        ),
                    )
                  },
              )
        } catch (e: Exception) {
          call.respondBykcError(e, this)
        }
      }
    }

    /** GET /api/v1/bykc/courses/chosen 获取当前用户已报名的博雅课程。 */
    get("/courses/chosen") {
      val username = call.jwtUsername!!
      call.observeBusinessOperation("bykc", "list_chosen_courses") {
        try {
          val chosenCourses = bykcService.getChosenCourses(username)
          call.respond(HttpStatusCode.OK, chosenCourses)
        } catch (e: Exception) {
          call.respondBykcError(e, this)
        }
      }
    }

    /** GET /api/v1/bykc/courses/{courseId} 获取单门课程的详细信息。 */
    get("/courses/{courseId}") {
      val username = call.jwtUsername!!
      val courseId =
          call.parameters["courseId"]?.toLongOrNull()
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      call.observeBusinessOperation("bykc", "get_course_detail") {
        try {
          val courseDetail = bykcService.getCourseDetail(username, courseId)
          call.respond(HttpStatusCode.OK, courseDetail)
        } catch (e: Exception) {
          call.respondBykcError(e, this)
        }
      }
    }

    /** POST /api/v1/bykc/courses/{courseId}/sign 执行签到或签退操作。 */
    post("/courses/{courseId}/sign") {
      val username = call.jwtUsername!!
      val courseId =
          call.parameters["courseId"]?.toLongOrNull()
              ?: return@post call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      val signRequest =
          try {
            call.receive<BykcSignRequest>()
          } catch (e: Exception) {
            return@post call.respondError(HttpStatusCode.BadRequest, "invalid_request")
          }

      call.observeBusinessOperation("bykc", "sign_course") {
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
                markBusinessFailure()
                call.respond(
                    HttpStatusCode.BadRequest,
                    ErrorResponse(
                        ErrorDetails(
                            "sign_failed",
                            cn.edu.ubaa.auth.userFacingMessage("sign_failed"),
                        )
                    ),
                )
              },
          )
        } catch (e: Exception) {
          call.respondBykcError(e, this)
        }
      }
    }
  }
}

private suspend fun ApplicationCall.respondBykcError(
    error: Exception,
    scope: BusinessOperationScope? = null,
) {
  if (error is CancellationException) throw error
  val (status, details) =
      when (error) {
        is LoginException ->
            HttpStatusCode.Unauthorized to
                ErrorDetails(
                    "unauthenticated",
                    cn.edu.ubaa.auth.userFacingMessage("unauthenticated"),
                )
        is UpstreamTimeoutException ->
            HttpStatusCode.GatewayTimeout to
                ErrorDetails(error.code, cn.edu.ubaa.auth.userFacingMessage(error.code))
        is BykcException ->
            HttpStatusCode.BadGateway to
                ErrorDetails("bykc_error", cn.edu.ubaa.auth.userFacingMessage("bykc_error"))
        else ->
            HttpStatusCode.InternalServerError to
                ErrorDetails(
                    "internal_server_error",
                    cn.edu.ubaa.auth.userFacingMessage("internal_server_error"),
                )
      }
  when (error) {
    is LoginException -> scope?.markUnauthenticated()
    is UpstreamTimeoutException -> scope?.markTimeout()
    is BykcException -> scope?.markBusinessFailure()
    else -> scope?.markError()
  }
  respond(status, ErrorResponse(details))
}
