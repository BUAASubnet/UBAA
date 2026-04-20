package cn.edu.ubaa.auth

import cn.edu.ubaa.api.SessionStatusResponse
import cn.edu.ubaa.auth.JwtAuth.getUserSession
import cn.edu.ubaa.metrics.LoginConnectionMode
import cn.edu.ubaa.metrics.LoginMetricsSink
import cn.edu.ubaa.metrics.LoginSuccessMode
import cn.edu.ubaa.metrics.NoOpLoginMetricsSink
import cn.edu.ubaa.metrics.observeBusinessOperation
import cn.edu.ubaa.model.dto.CaptchaRequiredResponse
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.LoginStatsConnectionMode
import cn.edu.ubaa.model.dto.LoginStatsReportRequest
import cn.edu.ubaa.model.dto.LoginStatsSuccessMode
import cn.edu.ubaa.model.dto.TokenRefreshRequest
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

/** 统一的错误响应类。 */
@Serializable data class ErrorResponse(val error: ErrorDetails)

/**
 * 错误详细信息。
 *
 * @property code 错误码。
 * @property message 错误描述。
 */
@Serializable data class ErrorDetails(val code: String, val message: String)

/** 注册认证相关路由。 包含预加载、登录、状态查询、注销和验证码获取。 */
fun Route.authRouting(
    loginMetricsSink: LoginMetricsSink = NoOpLoginMetricsSink,
    sessionManager: SessionManager = GlobalSessionManager.instance,
    authService: AuthService =
        AuthService(
            sessionManager,
            loginMetricsSink = loginMetricsSink,
            distributedLockManager = GlobalDistributedLockManager.instance,
        ),
) {

  route("/api/v1/auth") {
    /** POST /api/v1/auth/preload 预加载登录状态。为指定 clientId 创建或恢复一个预登录会话，并探测是否需要验证码。 */
    post("/preload") {
      call.observeBusinessOperation("auth", "preload") {
        try {
          val request = call.receive<cn.edu.ubaa.model.dto.LoginPreloadRequest>()
          application.log.info("Preloading login state for clientId: {}", request.clientId)
          val preloadResponse = authService.preloadLoginState(request.clientId)
          call.respond(HttpStatusCode.OK, preloadResponse)
        } catch (e: ContentTransformationException) {
          markBusinessFailure()
          call.respondError(HttpStatusCode.BadRequest, "invalid_request", "请提供有效的客户端标识")
        } catch (e: Exception) {
          markError()
          application.log.error("An unexpected error occurred during login preload.", e)
          call.respondError(
              HttpStatusCode.InternalServerError,
              "internal_server_error",
              "登录状态加载失败，请稍后重试",
          )
        }
      }
    }

    /** POST /api/v1/auth/login 用户登录接口。支持普通登录和带验证码/执行标识的二次提交。 */
    post("/login") {
      call.observeBusinessOperation("auth", "login") {
        var requestUsername: String? = null
        try {
          val request = call.receive<LoginRequest>()
          requestUsername = request.username
          application.log.info("Login attempt for user: {}", request.username)
          val loginResponse = authService.login(request)
          application.log.info("Login successful for user: {}", request.username)
          call.respond(HttpStatusCode.OK, loginResponse)
        } catch (e: ContentTransformationException) {
          markBusinessFailure()
          call.respondError(HttpStatusCode.BadRequest, "invalid_request", "登录请求格式不正确")
        } catch (e: CaptchaRequiredException) {
          markBusinessFailure()
          call.respond(
              HttpStatusCode.UnprocessableEntity,
              CaptchaRequiredResponse(e.captchaInfo, e.execution, e.message ?: "需要验证码"),
          )
        } catch (e: LoginException) {
          markUnauthenticated()
          call.respondError(HttpStatusCode.Unauthorized, "invalid_credentials")
        } catch (e: UpstreamTimeoutException) {
          markTimeout()
          application.log.warn("Login timed out for user {}", requestUsername ?: "unknown", e)
          call.respondError(HttpStatusCode.ServiceUnavailable, e.code)
        } catch (e: Exception) {
          markError()
          application.log.error("An unexpected error occurred during login.", e)
          call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
        }
      }
    }

    post("/login-stats") {
      call.observeBusinessOperation("auth", "login_stats") {
        try {
          val request = call.receive<LoginStatsReportRequest>()
          if (request.username.isBlank()) {
            markBusinessFailure()
            call.respondError(HttpStatusCode.BadRequest, "invalid_request", "请提供有效的用户名")
            return@observeBusinessOperation
          }
          loginMetricsSink.recordSuccess(
              request.username,
              request.successMode.toMetricMode(),
              request.connectionMode.toMetricMode(),
          )
          call.respond(HttpStatusCode.OK)
        } catch (e: ContentTransformationException) {
          markBusinessFailure()
          call.respondError(HttpStatusCode.BadRequest, "invalid_request", "登录统计请求格式不正确")
        } catch (e: Exception) {
          markError()
          application.log.error("An unexpected error occurred during login stats reporting.", e)
          call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
        }
      }
    }

    /** POST /api/v1/auth/refresh 使用 refresh token 换取新的 token 对。 */
    post("/refresh") {
      call.observeBusinessOperation("auth", "refresh") {
        try {
          val request = call.receive<TokenRefreshRequest>()
          val refreshResponse = authService.refreshTokens(request.refreshToken)
          if (refreshResponse != null) {
            call.respond(HttpStatusCode.OK, refreshResponse)
          } else {
            markBusinessFailure()
            call.respondError(HttpStatusCode.Unauthorized, "invalid_refresh_token")
          }
        } catch (e: ContentTransformationException) {
          markBusinessFailure()
          call.respondError(HttpStatusCode.BadRequest, "invalid_request", "刷新令牌请求格式不正确")
        } catch (e: Exception) {
          markError()
          application.log.error("An unexpected error occurred during token refresh.", e)
          call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
        }
      }
    }

    /** GET /api/v1/auth/status 查询当前会话状态。需携带有效的 JWT 令牌。 */
    get("/status") {
      call.observeBusinessOperation("auth", "status") {
        try {
          val session = call.getUserSession(sessionManager)
          if (session == null) {
            markUnauthenticated()
            call.respondError(HttpStatusCode.Unauthorized, "invalid_token")
            return@observeBusinessOperation
          }

          when (val validationResult = authService.validateSession(session)) {
            is AuthService.SessionValidationResult.Valid -> {
              application.log.info(
                  "Session status check: user {} is authenticated",
                  validationResult.userData.name,
              )
              val statusResponse =
                  SessionStatusResponse(
                      user = validationResult.userData,
                      lastActivity = session.lastActivity().toString(),
                      authenticatedAt = session.authenticatedAt.toString(),
                  )
              call.respond(HttpStatusCode.OK, statusResponse)
            }
            AuthService.SessionValidationResult.Invalid -> {
              markUnauthenticated()
              sessionManager.invalidateSession(session.username)
              application.log.warn("Session status check failed: invalid or expired token")
              call.respondError(HttpStatusCode.Unauthorized, "invalid_token")
            }
            is AuthService.SessionValidationResult.RetryableFailure -> {
              markTimeout()
              application.log.warn(
                  "Session status check deferred for user {} due to upstream timeout",
                  session.username,
                  validationResult.cause,
              )
              call.respondError(HttpStatusCode.ServiceUnavailable, "auth_upstream_timeout")
            }
          }
        } catch (e: Exception) {
          markError()
          application.log.error("An unexpected error occurred during status check.", e)
          call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
        }
      }
    }

    /** POST /api/v1/auth/logout 用户注销接口。清理服务端会话并尝试使上游 SSO 失效。 */
    post("/logout") {
      call.observeBusinessOperation("auth", "logout") {
        try {
          val session = call.getUserSession(sessionManager)
          if (session != null) {
            authService.logout(session.username)
            call.respond(HttpStatusCode.OK, mapOf("message" to "Logged out successfully"))
          } else {
            markUnauthenticated()
            call.respondError(HttpStatusCode.Unauthorized, "invalid_token")
          }
        } catch (e: Exception) {
          markError()
          application.log.error("An unexpected error occurred during logout.", e)
          call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
        }
      }
    }

    /** GET /api/v1/auth/captcha/{captchaId} 获取验证码图片。 */
    get("/captcha/{captchaId}") {
      call.observeBusinessOperation("auth", "captcha") {
        try {
          val captchaId = call.parameters["captchaId"]
          if (captchaId.isNullOrBlank()) {
            markBusinessFailure()
            call.respondError(HttpStatusCode.BadRequest, "invalid_request", "请提供验证码标识")
            return@observeBusinessOperation
          }

          val imageBytes =
              authService.getCaptchaImage(cn.edu.ubaa.utils.HttpClients.sharedClient, captchaId)
          if (imageBytes != null) {
            call.respondBytes(bytes = imageBytes, contentType = ContentType.Image.JPEG)
          } else {
            markBusinessFailure()
            call.respondError(HttpStatusCode.NotFound, "captcha_not_found")
          }
        } catch (e: Exception) {
          markError()
          application.log.error("An unexpected error occurred during CAPTCHA fetch.", e)
          call.respondError(HttpStatusCode.InternalServerError, "internal_server_error")
        }
      }
    }
  }
}

private fun LoginStatsSuccessMode.toMetricMode(): LoginSuccessMode =
    when (this) {
      LoginStatsSuccessMode.MANUAL -> LoginSuccessMode.MANUAL
      LoginStatsSuccessMode.PRELOAD_AUTO -> LoginSuccessMode.PRELOAD_AUTO
    }

private fun LoginStatsConnectionMode.toMetricMode(): LoginConnectionMode =
    when (this) {
      LoginStatsConnectionMode.DIRECT -> LoginConnectionMode.DIRECT
      LoginStatsConnectionMode.WEBVPN -> LoginConnectionMode.WEBVPN
      LoginStatsConnectionMode.SERVER_RELAY -> LoginConnectionMode.SERVER_RELAY
    }
