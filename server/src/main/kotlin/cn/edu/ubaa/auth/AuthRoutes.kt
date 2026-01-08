package cn.edu.ubaa.auth

import cn.edu.ubaa.api.SessionStatusResponse
import cn.edu.ubaa.auth.JwtAuth.getUserSession
import cn.edu.ubaa.model.dto.CaptchaRequiredResponse
import cn.edu.ubaa.model.dto.LoginRequest
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
fun Route.authRouting() {
  val sessionManager = GlobalSessionManager.instance
  val authService = AuthService(sessionManager)

  route("/api/v1/auth") {
    /** POST /api/v1/auth/preload 预加载登录状态。为指定 clientId 创建或恢复一个预登录会话，并探测是否需要验证码。 */
    post("/preload") {
      try {
        val request = call.receive<cn.edu.ubaa.model.dto.LoginPreloadRequest>()
        application.log.info("Preloading login state for clientId: {}", request.clientId)
        val preloadResponse = authService.preloadLoginState(request.clientId)
        call.respond(HttpStatusCode.OK, preloadResponse)
      } catch (e: ContentTransformationException) {
        call.respond(
          HttpStatusCode.BadRequest,
          ErrorResponse(
            ErrorDetails("invalid_request", "Invalid request body: clientId is required")
          ),
        )
      } catch (e: Exception) {
        application.log.error("An unexpected error occurred during login preload.", e)
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(ErrorDetails("internal_server_error", "Failed to preload login state")),
        )
      }
    }

    /** POST /api/v1/auth/login 用户登录接口。支持普通登录和带验证码/执行标识的二次提交。 */
    post("/login") {
      try {
        val request = call.receive<LoginRequest>()
        application.log.info("Login attempt for user: {}", request.username)
        val loginResponse = authService.loginWithToken(request)
        application.log.info("Login successful for user: {}", request.username)
        call.respond(HttpStatusCode.OK, loginResponse)
      } catch (e: ContentTransformationException) {
        call.respond(
          HttpStatusCode.BadRequest,
          ErrorResponse(ErrorDetails("invalid_request", "Invalid request body: ${e.message}")),
        )
      } catch (e: CaptchaRequiredException) {
        call.respond(
          HttpStatusCode.UnprocessableEntity, // 需验证码
          CaptchaRequiredResponse(e.captchaInfo, e.execution, e.message ?: "需要验证码"),
        )
      } catch (e: LoginException) {
        call.respond(
          HttpStatusCode.Unauthorized,
          ErrorResponse(ErrorDetails("invalid_credentials", e.message ?: "Login failed")),
        )
      } catch (e: Exception) {
        application.log.error("An unexpected error occurred during login.", e)
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(
            ErrorDetails("internal_server_error", "An unexpected server error occurred.")
          ),
        )
      }
    }

    /** GET /api/v1/auth/status 查询当前会话状态。需携带有效的 JWT 令牌。 */
    get("/status") {
      try {
        val session = call.getUserSession()
        if (session != null) {
          application.log.info(
            "Session status check: user {} is authenticated",
            session.userData.name,
          )
          val statusResponse =
            SessionStatusResponse(
              user = session.userData,
              lastActivity = session.lastActivity().toString(),
              authenticatedAt = session.authenticatedAt.toString(),
            )
          call.respond(HttpStatusCode.OK, statusResponse)
        } else {
          application.log.warn("Session status check failed: invalid or expired token")
          call.respond(
            HttpStatusCode.Unauthorized,
            ErrorResponse(ErrorDetails("invalid_token", "Invalid or expired JWT token")),
          )
        }
      } catch (e: Exception) {
        application.log.error("An unexpected error occurred during status check.", e)
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(
            ErrorDetails("internal_server_error", "An unexpected server error occurred.")
          ),
        )
      }
    }

    /** POST /api/v1/auth/logout 用户注销接口。清理服务端会话并尝试使上游 SSO 失效。 */
    post("/logout") {
      try {
        val session = call.getUserSession()
        if (session != null) {
          authService.logout(session.username)
          call.respond(HttpStatusCode.OK, mapOf("message" to "Logged out successfully"))
        } else {
          call.respond(
            HttpStatusCode.Unauthorized,
            ErrorResponse(ErrorDetails("invalid_token", "Invalid or expired JWT token")),
          )
        }
      } catch (e: Exception) {
        application.log.error("An unexpected error occurred during logout.", e)
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(
            ErrorDetails("internal_server_error", "An unexpected server error occurred.")
          ),
        )
      }
    }

    /** GET /api/v1/auth/captcha/{captchaId} 获取验证码图片。 */
    get("/captcha/{captchaId}") {
      try {
        val captchaId = call.parameters["captchaId"]
        if (captchaId.isNullOrBlank()) {
          call.respond(
            HttpStatusCode.BadRequest,
            ErrorResponse(ErrorDetails("invalid_request", "captchaId parameter is required")),
          )
          return@get
        }

        val imageBytes =
          authService.getCaptchaImage(cn.edu.ubaa.utils.HttpClients.sharedClient, captchaId)
        if (imageBytes != null) {
          call.respondBytes(bytes = imageBytes, contentType = ContentType.Image.JPEG)
        } else {
          call.respond(
            HttpStatusCode.NotFound,
            ErrorResponse(ErrorDetails("captcha_not_found", "CAPTCHA image not found")),
          )
        }
      } catch (e: Exception) {
        application.log.error("An unexpected error occurred during CAPTCHA fetch.", e)
        call.respond(
          HttpStatusCode.InternalServerError,
          ErrorResponse(
            ErrorDetails("internal_server_error", "An unexpected server error occurred.")
          ),
        )
      }
    }
  }
}
