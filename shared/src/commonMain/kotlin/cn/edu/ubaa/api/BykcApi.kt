package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.body
import io.ktor.client.request.*
import io.ktor.http.*

/** BYKC (博雅课程) service for managing liberal arts courses */
class BykcApi(private val apiClient: ApiClient = ApiClientProvider.shared) {

    suspend fun getProfile(): Result<BykcUserProfileDto> {
        return safeApiCall { apiClient.getClient().get("api/v1/bykc/profile") }
    }

    suspend fun getCourses(
        page: Int = 1,
        size: Int = 200,
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

    suspend fun getChosenCourses(): Result<List<BykcChosenCourseDto>> {
        return safeApiCall { apiClient.getClient().get("api/v1/bykc/courses/chosen") }
    }

    suspend fun getStatistics(): Result<BykcStatisticsDto> {
        return safeApiCall { apiClient.getClient().get("api/v1/bykc/statistics") }
    }

    suspend fun selectCourse(courseId: Long): Result<BykcSuccessResponse> {
        return safeApiCall {
            apiClient.getClient().post("api/v1/bykc/courses/$courseId/select") {
                contentType(ContentType.Application.Json)
            }
        }
    }

    suspend fun deselectCourse(courseId: Long): Result<BykcSuccessResponse> {
        return safeApiCall { 
            apiClient.getClient().delete("api/v1/bykc/courses/$courseId/select") 
        }
    }

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
