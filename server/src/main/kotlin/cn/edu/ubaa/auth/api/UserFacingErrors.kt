package cn.edu.ubaa.auth

import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.install
import io.ktor.server.plugins.ContentTransformationException
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.plugins.statuspages.exception
import io.ktor.server.request.httpMethod
import io.ktor.server.request.uri
import io.ktor.server.response.respond

internal fun userFacingMessage(code: String, fallback: String? = null): String {
  return when (code) {
    "invalid_request" -> "请求参数不正确，请检查后重试"
    "invalid_credentials" -> "账号或密码错误，请重试"
    "invalid_refresh_token",
    "invalid_token",
    "unauthenticated" -> "登录状态已失效，请重新登录"
    "auth_upstream_timeout" -> "认证服务响应超时，请稍后重试"
    "auth_lock_timeout" -> "当前登录请求较多，请稍后重试"
    "captcha_not_found" -> "验证码已失效，请刷新后重试"
    "captcha_error" -> "验证码处理失败，请稍后重试"
    "missing_client_version" -> "缺少客户端版本信息"
    "internal_server_error" -> "服务器开小差了，请稍后再试"
    "unsupported_portal" -> "当前账号类型暂不支持该功能"
    "already_selected" -> "您已报名过该课程，请勿重复报名"
    "course_full" -> "该课程人数已满，请选择其他课程"
    "course_not_selectable" -> "该课程当前不可报名"
    "select_failed" -> "报名失败，请稍后重试"
    "deselect_failed" -> "退选失败，请稍后重试"
    "sign_failed" -> "签到失败，请稍后重试"
    "signin_failed" -> "签到失败，请稍后重试"
    "signin_load_failed" -> "签到信息加载失败，请稍后重试"
    "bykc_error" -> "博雅课程服务暂时不可用，请稍后重试"
    "bykc_timeout" -> "博雅课程服务响应超时，请稍后重试"
    "cgyy_error" -> "研讨室服务暂时不可用，请稍后重试"
    "cgyy_timeout" -> "研讨室服务响应超时，请稍后重试"
    "reservation_invalid",
    "reservation_token_missing" -> "预约信息已失效，请刷新后重试"
    "day_info_failed" -> "获取研讨室可用信息失败，请稍后重试"
    "spoc_auth_failed" -> "SPOC 登录状态异常，请重新登录后重试"
    "spoc_error" -> "SPOC 服务暂时不可用，请稍后重试"
    "ygdk_error" -> "阳光打卡服务暂时不可用，请稍后重试"
    "ygdk_timeout" -> "阳光打卡服务响应超时，请稍后重试"
    "schedule_error" -> "课表查询失败，请稍后重试"
    "exam_error" -> "考试信息查询失败，请稍后重试"
    "user_info_failed" -> "用户信息查询失败，请稍后重试"
    "classroom_query_failed" -> "空闲教室查询失败，请稍后重试"
    "evaluation_error" -> "评教服务暂时不可用，请稍后重试"
    else -> fallback ?: "请求失败，请稍后重试"
  }
}

internal suspend fun ApplicationCall.respondError(
    status: HttpStatusCode,
    code: String,
    fallback: String? = null,
) {
  respond(status, ErrorResponse(ErrorDetails(code, userFacingMessage(code, fallback))))
}

internal fun Application.configureGlobalErrorHandling() {
  install(StatusPages) {
    exception<ContentTransformationException> { call, cause ->
      call.application.environment.log.debug(
          "Failed to transform request body for ${call.requestDescription()}",
          cause,
      )
      if (!call.response.isCommitted) {
        call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      }
    }

    exception<IllegalStateException> { call, cause ->
      if (cause.message == "No valid session found for request") {
        call.application.environment.log.debug(
            "Missing valid session for ${call.requestDescription()}"
        )
        if (!call.response.isCommitted) {
          call.respondError(HttpStatusCode.Unauthorized, "invalid_token")
        }
      } else {
        call.application.environment.log.error(
            "Unexpected application state for ${call.requestDescription()}",
            cause,
        )
        if (!call.response.isCommitted) {
          call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
        }
      }
    }

    exception<Throwable> { call, cause ->
      call.application.environment.log.error(
          "Unhandled exception for ${call.requestDescription()}",
          cause,
      )
      if (!call.response.isCommitted) {
        call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
      }
    }
  }
}

private fun ApplicationCall.requestDescription(): String =
    "${request.httpMethod.value} ${request.uri}"
