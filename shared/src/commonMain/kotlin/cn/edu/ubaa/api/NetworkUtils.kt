package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.CaptchaRequiredResponse
import io.ktor.client.call.body
import io.ktor.client.statement.HttpResponse
import io.ktor.http.HttpStatusCode
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
      HttpStatusCode.OK -> {
        Result.success(response.body<T>())
      }
      HttpStatusCode.Unauthorized -> {
        val error = runCatching { response.body<ApiErrorResponse>() }.getOrNull()
        Result.failure(Exception(error?.error?.message ?: "Unauthorized"))
      }
      HttpStatusCode.UnprocessableEntity -> {
        val error = runCatching { response.body<CaptchaRequiredResponse>() }.getOrNull()
        if (error != null) {
          Result.failure(
            CaptchaRequiredClientException(error.captcha, error.execution, error.message)
          )
        } else {
          Result.failure(Exception("CAPTCHA required but failed to parse response"))
        }
      }
      else -> {
        val error = runCatching { response.body<ApiErrorResponse>() }.getOrNull()
        val message = error?.error?.message ?: "Request failed with status: ${response.status}"
        Result.failure(Exception(message))
      }
    }
  } catch (e: Exception) {
    Result.failure(e)
  }
}
