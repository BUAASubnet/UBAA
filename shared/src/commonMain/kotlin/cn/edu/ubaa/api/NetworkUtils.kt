package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.CaptchaRequiredResponse
import io.ktor.client.call.body
import io.ktor.client.network.sockets.ConnectTimeoutException
import io.ktor.client.network.sockets.SocketTimeoutException
import io.ktor.client.plugins.HttpRequestTimeoutException
import io.ktor.client.statement.HttpResponse
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable

/**
 * 业务 API 错误响应体。
 *
 * @property error 错误详细信息。
 */
@Serializable data class ApiErrorResponse(val error: ApiErrorDetails)

/**
 * 错误详细信息。
 *
 * @property code 错误代码（如 "invalid_token"）。
 * @property message 对用户友好的错误描述。
 */
@Serializable data class ApiErrorDetails(val code: String, val message: String)

/**
 * 客户端异常：需要输入验证码方可继续。
 *
 * @property captcha 验证码图片及标识信息。
 * @property execution SSO 执行标识。
 * @property message 提示消息。
 */
class CaptchaRequiredClientException(
    val captcha: CaptchaInfo,
    val execution: String,
    message: String,
) : Exception(message)

class ApiCallException(
    message: String,
    val status: HttpStatusCode? = null,
    val code: String? = null,
) : Exception(message)

internal fun userFacingMessageForCode(code: String?, status: HttpStatusCode): String {
  return when (code) {
    "invalid_request" -> "请求参数不正确，请检查后重试"
    "invalid_credentials" -> "账号或密码错误，请重试"
    "invalid_refresh_token",
    "invalid_token",
    "unauthenticated",
    "unauthorized" -> "登录状态已失效，请重新登录"
    "auth_upstream_timeout" -> "认证服务响应超时，请稍后重试"
    "captcha_not_found" -> "验证码已失效，请刷新后重试"
    "captcha_error" -> "验证码处理失败，请稍后重试"
    "missing_client_version" -> "缺少客户端版本信息"
    "unsupported_portal" -> "当前账号类型暂不支持该功能"
    "already_selected" -> "您已报名过该课程，请勿重复报名"
    "course_full" -> "该课程人数已满，请选择其他课程"
    "course_not_selectable" -> "该课程当前不可报名"
    "select_failed" -> "报名失败，请稍后重试"
    "deselect_failed" -> "退选失败，请稍后重试"
    "sign_failed",
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
    "grade_error" -> "成绩查询失败，请稍后重试"
    "user_info_failed" -> "用户信息查询失败，请稍后重试"
    "classroom_query_failed" -> "空闲教室查询失败，请稍后重试"
    "evaluation_error" -> "评教服务暂时不可用，请稍后重试"
    "internal_server_error" -> "服务器开小差了，请稍后再试"
    else -> userFacingMessageForStatus(status)
  }
}

internal fun userFacingMessageForStatus(status: HttpStatusCode): String {
  return when (status) {
    HttpStatusCode.BadRequest -> "请求参数不正确，请检查后重试"
    HttpStatusCode.Unauthorized -> "登录状态已失效，请重新登录"
    HttpStatusCode.Forbidden -> "当前没有权限执行该操作"
    HttpStatusCode.NotFound -> "请求的资源不存在或已失效"
    HttpStatusCode.RequestTimeout,
    HttpStatusCode.GatewayTimeout -> "请求超时，请稍后重试"
    HttpStatusCode.BadGateway,
    HttpStatusCode.ServiceUnavailable -> "服务暂时不可用，请稍后重试"
    HttpStatusCode.InternalServerError -> "服务器开小差了，请稍后再试"
    else -> "请求失败，请稍后重试"
  }
}

@PublishedApi
internal suspend fun HttpResponse.userFacingErrorMessage(): String {
  val error = runCatching { body<ApiErrorResponse>() }.getOrNull()
  return userFacingMessageForCode(error?.error?.code, status)
}

@PublishedApi
internal suspend fun HttpResponse.toApiCallException(): ApiCallException {
  val error = runCatching { body<ApiErrorResponse>() }.getOrNull()
  val code = error?.error?.code
  return ApiCallException(
      message = userFacingMessageForCode(code, status),
      status = status,
      code = code,
  )
}

@PublishedApi
internal fun Throwable.toUserFacingApiException(
    defaultMessage: String = "网络异常，请检查连接后重试"
): Exception {
  if (this is CancellationException) throw this
  return when (this) {
    is ApiCallException -> this
    is CaptchaRequiredClientException -> this
    is HttpRequestTimeoutException,
    is ConnectTimeoutException,
    is SocketTimeoutException -> ApiCallException("请求超时，请稍后重试")
    else -> ApiCallException(defaultMessage)
  }
}

/**
 * 标准化 API 调用包装器。 统一处理 HTTP 状态码、解析异常以及业务错误响应，并封装为 [Result] 返回。
 *
 * @param T 期望的成功响应体类型。
 * @param call 执行 HTTP 请求的挂起函数。
 * @return 包含结果对象或异常的 [Result]。
 */
suspend inline fun <reified T> safeApiCall(call: () -> HttpResponse): Result<T> {
  return try {
    val response = call()
    when (response.status) {
      HttpStatusCode.OK -> Result.success(response.body<T>())
      HttpStatusCode.Unauthorized -> Result.failure(response.toApiCallException())
      HttpStatusCode.UnprocessableEntity -> {
        val error = runCatching { response.body<CaptchaRequiredResponse>() }.getOrNull()
        if (error != null) {
          Result.failure(
              CaptchaRequiredClientException(error.captcha, error.execution, error.message)
          )
        } else {
          Result.failure(ApiCallException("需要验证码，请刷新后重试"))
        }
      }
      else -> Result.failure(response.toApiCallException())
    }
  } catch (e: Exception) {
    Result.failure(e.toUserFacingApiException())
  }
}
