package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.body
import io.ktor.client.request.*
import io.ktor.http.*

/**
 * 博雅课程 (BYKC) API 服务。
 * 提供课程查询、详情查看、选课、退选、签到以及修读统计等功能。
 * @param apiClient 使用的 ApiClient 实例。
 */
class BykcApi(private val apiClient: ApiClient = ApiClientProvider.shared) {

    /**
     * 获取博雅系统中的用户个人资料。
     * @return 用户基本信息。
     */
    suspend fun getProfile(): Result<BykcUserProfileDto> {
        return safeApiCall { apiClient.getClient().get("api/v1/bykc/profile") }
    }

    /**
     * 分页查询博雅课程列表。
     *
     * @param page 页码，从 1 开始。
     * @param size 每页记录数。
     * @param all 是否包含已结束/过期的课程。
     * @return 课程分页结果响应。
     */
    suspend fun getCourses(
        page: Int = 1,
        size: Int = 20,
        all: Boolean = false
    ): Result<BykcCoursesResponse> {
        return safeApiCall {
            apiClient.getClient().get("api/v1/bykc/courses") {
                parameter("page", page)
                parameter("size", size)
                parameter("all", all)
            }
        }
    }

    /**
     * 获取指定博雅课程的详细信息。
     *
     * @param courseId 课程唯一标识。
     * @return 课程详细信息，包含签到配置等。
     */
    suspend fun getCourseDetail(courseId: Long): Result<BykcCourseDetailDto> {
        return try {
            val response = apiClient.getClient().get("api/v1/bykc/courses/$courseId")
            
            when (response.status) {
                HttpStatusCode.OK -> Result.success(response.body())
                HttpStatusCode.NotFound -> Result.failure(Exception("课程不存在"))
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

    /**
     * 获取当前用户已选（已报名）的博雅课程列表。
     * @return 已选课程列表。
     */
    suspend fun getChosenCourses(): Result<List<BykcChosenCourseDto>> {
        return safeApiCall { apiClient.getClient().get("api/v1/bykc/courses/chosen") }
    }

    /**
     * 获取当前用户的博雅修读次数统计信息。
     * @return 各分类的统计结果。
     */
    suspend fun getStatistics(): Result<BykcStatisticsDto> {
        return safeApiCall { apiClient.getClient().get("api/v1/bykc/statistics") }
    }

    /**
     * 选择（报名）一门博雅课程。
     * @param courseId 课程 ID。
     * @return 操作成功响应。
     */
    suspend fun selectCourse(courseId: Long): Result<BykcSuccessResponse> {
        return safeApiCall {
            apiClient.getClient().post("api/v1/bykc/courses/$courseId/select") {
                contentType(ContentType.Application.Json)
            }
        }
    }

    /**
     * 退选（取消报名）一门博雅课程。
     * @param courseId 课程 ID。
     * @return 操作成功响应。
     */
    suspend fun deselectCourse(courseId: Long): Result<BykcSuccessResponse> {
        return safeApiCall { 
            apiClient.getClient().delete("api/v1/bykc/courses/$courseId/select") 
        }
    }

    /**
     * 执行博雅课程签到或签退。
     *
     * @param courseId 课程 ID。
     * @param lat 签到时的纬度（可选，若服务端未配置范围则需提供）。
     * @param lng 签到时的经度（可选）。
     * @param signType 类型：1=签到, 2=签退。
     * @return 操作成功响应。
     */
    suspend fun signCourse(
        courseId: Long,
        lat: Double? = null,
        lng: Double? = null,
        signType: Int
    ): Result<BykcSuccessResponse> {
        return safeApiCall {
            apiClient.getClient().post("api/v1/bykc/courses/$courseId/sign") {
                contentType(ContentType.Application.Json)
                setBody(BykcSignRequest(courseId, lat, lng, signType))
            }
        }
    }
}