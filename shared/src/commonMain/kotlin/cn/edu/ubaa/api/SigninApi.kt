package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.request.*
import io.ktor.http.*

/**
 * 课堂签到 API 服务。
 * 用于查询今日可签到的课堂及执行签到动作。
 * @param apiClient 使用的 ApiClient 实例。
 */
class SigninApi(private val apiClient: ApiClient = ApiClientProvider.shared) {

    /**
     * 获取今日所有有签到任务的课堂列表。
     * @return 签到状态响应，包含课堂列表。
     */
    suspend fun getTodayClasses(): Result<SigninStatusResponse> {
        return safeApiCall { apiClient.getClient().get("api/v1/signin/today") }
    }

    /**
     * 执行课堂签到。
     *
     * @param courseId 课程 ID。
     * @return 签到操作执行结果。
     */
    suspend fun performSignin(courseId: String): Result<SigninActionResponse> {
        return safeApiCall {
            apiClient.getClient().post("api/v1/signin/do") { parameter("courseId", courseId) }
        }
    }
}