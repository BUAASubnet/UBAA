package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.request.*
import io.ktor.http.*

/** 课程签到 API */
class SigninApi(private val apiClient: ApiClient = ApiClientProvider.shared) {

    suspend fun getTodayClasses(): Result<SigninStatusResponse> {
        return safeApiCall { apiClient.getClient().get("api/v1/signin/today") }
    }

    suspend fun performSignin(courseId: String): Result<SigninActionResponse> {
        return safeApiCall {
            apiClient.getClient().post("api/v1/signin/do") { parameter("courseId", courseId) }
        }
    }
}
