package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.CaptchaRequiredResponse
import io.ktor.client.call.body
import io.ktor.client.statement.HttpResponse
import io.ktor.http.HttpStatusCode
import kotlinx.serialization.Serializable

@Serializable data class ApiErrorResponse(val error: ApiErrorDetails)

@Serializable data class ApiErrorDetails(val code: String, val message: String)

/** 客户端异常：需要验证码 */
class CaptchaRequiredClientException(
        val captcha: CaptchaInfo,
        val execution: String,
        message: String
) : Exception(message)

/** 标准化 API 调用包装器。 统一处理异常并返回 Result<T>。 */
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
                            CaptchaRequiredClientException(
                                    error.captcha,
                                    error.execution,
                                    error.message
                            )
                    )
                } else {
                    Result.failure(Exception("CAPTCHA required but failed to parse response"))
                }
            }
            else -> {
                val error = runCatching { response.body<ApiErrorResponse>() }.getOrNull()
                val message =
                        error?.error?.message ?: "Request failed with status: ${response.status}"
                Result.failure(Exception(message))
            }
        }
    } catch (e: Exception) {
        Result.failure(e)
    }
}
