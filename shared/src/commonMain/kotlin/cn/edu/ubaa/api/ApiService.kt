package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*

/** Authentication service for handling login/logout operations */
object ApiClientProvider {
    val shared: ApiClient by lazy { ApiClient() }
}

class AuthService(private val apiClient: ApiClient = ApiClientProvider.shared) {

    fun applyStoredToken() {
        TokenStore.get()?.let { apiClient.updateToken(it) }
    }

    suspend fun login(
            username: String,
            password: String,
            captcha: String? = null
    ): Result<LoginResponse> {
        return try {
            val response =
                    apiClient.getClient().post("api/v1/auth/login") {
                        contentType(ContentType.Application.Json)
                        setBody(LoginRequest(username, password, captcha))
                    }

            when (response.status) {
                HttpStatusCode.OK -> {
                    val loginResponse = response.body<LoginResponse>()
                    // Update the client with the new token
                    apiClient.updateToken(loginResponse.token)
                    Result.success(loginResponse)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                HttpStatusCode.UnprocessableEntity -> { // 422 - CAPTCHA required
                    val captchaResponse = response.body<CaptchaRequiredResponse>()
                    Result.failure(
                            CaptchaRequiredClientException(
                                    captchaResponse.captcha,
                                    captchaResponse.message
                            )
                    )
                }
                else -> {
                    Result.failure(Exception("Login failed with status: ${response.status}"))
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getAuthStatus(): Result<SessionStatusResponse> {
        return try {
            val response = apiClient.getClient().get("api/v1/auth/status")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val status = response.body<SessionStatusResponse>()
                    Result.success(status)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(Exception("Status check failed with status: ${response.status}"))
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun logout(): Result<Unit> {
        return try {
            // First attempt to logout from the server
            val serverResponse = apiClient.getClient().post("api/v1/auth/logout")

            // Then attempt SSO logout regardless of server response
            try {
                val ssoResponse = apiClient.getClient().get("https://sso.buaa.edu.cn/logout")
                println("SSO logout response: ${ssoResponse.status}")
            } catch (ssoException: Exception) {
                println(
                        "SSO logout failed (this is expected in some environments): ${ssoException.message}"
                )
            }

            when (serverResponse.status) {
                HttpStatusCode.OK -> {
                    // Close the API client after successful logout
                    TokenStore.clear()
                    apiClient.close()
                    Result.success(Unit)
                }
                HttpStatusCode.Unauthorized -> {
                    // Even if unauthorized, clear local state
                    TokenStore.clear()
                    apiClient.close()
                    Result.success(Unit)
                }
                else -> {
                    // Even if server logout fails, clear local state
                    TokenStore.clear()
                    apiClient.close()
                    Result.failure(Exception("Logout failed with status: ${serverResponse.status}"))
                }
            }
        } catch (e: Exception) {
            // Even if network request fails, clear local state
            TokenStore.clear()
            apiClient.close()
            Result.failure(e)
        }
    }
}

/** User service for fetching user information */
class UserService(private val apiClient: ApiClient = ApiClientProvider.shared) {

    suspend fun getUserInfo(): Result<UserInfo> {
        return try {
            val response = apiClient.getClient().get("api/v1/user/info")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val userInfo = response.body<UserInfo>()
                    Result.success(userInfo)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception("Failed to fetch user info with status: ${response.status}")
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

/** Schedule service for fetching course schedules */
class ScheduleService(private val apiClient: ApiClient = ApiClientProvider.shared) {

    suspend fun getTerms(): Result<List<Term>> {
        return try {
            val response = apiClient.getClient().get("api/v1/schedule/terms")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val terms = response.body<List<Term>>()
                    Result.success(terms)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception("Failed to fetch terms with status: ${response.status}")
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getWeeks(termCode: String): Result<List<Week>> {
        return try {
            val response =
                    apiClient.getClient().get("api/v1/schedule/weeks") {
                        parameter("termCode", termCode)
                    }

            when (response.status) {
                HttpStatusCode.OK -> {
                    val weeks = response.body<List<Week>>()
                    Result.success(weeks)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception("Failed to fetch weeks with status: ${response.status}")
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> {
        return try {
            val response =
                    apiClient.getClient().get("api/v1/schedule/week") {
                        parameter("termCode", termCode)
                        parameter("week", week)
                    }

            when (response.status) {
                HttpStatusCode.OK -> {
                    val schedule = response.body<WeeklySchedule>()
                    Result.success(schedule)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception("Failed to fetch schedule with status: ${response.status}")
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getTodaySchedule(): Result<List<TodayClass>> {
        return try {
            val response = apiClient.getClient().get("api/v1/schedule/today")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val todaySchedule = response.body<List<TodayClass>>()
                    Result.success(todaySchedule)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception(
                                    "Failed to fetch today's schedule with status: ${response.status}"
                            )
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

// Additional DTOs needed for API responses
@kotlinx.serialization.Serializable data class ApiErrorResponse(val error: ApiErrorDetails)

@kotlinx.serialization.Serializable
data class ApiErrorDetails(val code: String, val message: String)

@kotlinx.serialization.Serializable
data class SessionStatusResponse(
        val user: UserData,
        val lastActivity: String,
        val authenticatedAt: String
)

/** Client-side exception thrown when CAPTCHA is required for login */
class CaptchaRequiredClientException(val captchaInfo: CaptchaInfo, message: String) :
        Exception(message)

/** BYKC (博雅课程) service for managing liberal arts courses */
class BykcService(private val apiClient: ApiClient = ApiClientProvider.shared) {

    suspend fun getProfile(): Result<BykcUserProfileDto> {
        return try {
            val response = apiClient.getClient().get("api/v1/bykc/profile")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val profile = response.body<BykcUserProfileDto>()
                    Result.success(profile)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception(
                                    "Failed to fetch BYKC profile with status: ${response.status}"
                            )
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getCourses(
            page: Int = 1,
            size: Int = 200,
            all: Boolean = false
    ): Result<BykcCoursesResponse> {
        return try {
            val response =
                    apiClient.getClient().get("api/v1/bykc/courses") {
                        parameter("page", page)
                        parameter("size", size)
                        parameter("all", all)
                    }

            when (response.status) {
                HttpStatusCode.OK -> {
                    val coursesResponse = response.body<BykcCoursesResponse>()
                    Result.success(coursesResponse)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception(
                                    "Failed to fetch BYKC courses with status: ${response.status}"
                            )
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getCourseDetail(courseId: Long): Result<BykcCourseDetailDto> {
        return try {
            val response = apiClient.getClient().get("api/v1/bykc/courses/$courseId")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val detail = response.body<BykcCourseDetailDto>()
                    Result.success(detail)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                HttpStatusCode.NotFound -> {
                    Result.failure(Exception("课程不存在"))
                }
                else -> {
                    Result.failure(
                            Exception(
                                    "Failed to fetch course detail with status: ${response.status}"
                            )
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getChosenCourses(): Result<List<BykcChosenCourseDto>> {
        return try {
            val response = apiClient.getClient().get("api/v1/bykc/courses/chosen")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val courses = response.body<List<BykcChosenCourseDto>>()
                    Result.success(courses)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    Result.failure(
                            Exception(
                                    "Failed to fetch chosen courses with status: ${response.status}"
                            )
                    )
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun selectCourse(courseId: Long): Result<BykcSuccessResponse> {
        return try {
            val response =
                    apiClient.getClient().post("api/v1/bykc/courses/$courseId/select") {
                        contentType(ContentType.Application.Json)
                    }

            when (response.status) {
                HttpStatusCode.OK -> {
                    val successResponse = response.body<BykcSuccessResponse>()
                    Result.success(successResponse)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    try {
                        val error = response.body<ApiErrorResponse>()
                        Result.failure(Exception(error.error.message))
                    } catch (e: Exception) {
                        Result.failure(Exception("选课失败: ${response.status}"))
                    }
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun deselectCourse(courseId: Long): Result<BykcSuccessResponse> {
        return try {
            val response = apiClient.getClient().delete("api/v1/bykc/courses/$courseId/select")

            when (response.status) {
                HttpStatusCode.OK -> {
                    val successResponse = response.body<BykcSuccessResponse>()
                    Result.success(successResponse)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    try {
                        val error = response.body<ApiErrorResponse>()
                        Result.failure(Exception(error.error.message))
                    } catch (e: Exception) {
                        Result.failure(Exception("退选失败: ${response.status}"))
                    }
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun signCourse(
            courseId: Long,
            lat: Double? = null,
            lng: Double? = null,
            signType: Int
    ): Result<BykcSuccessResponse> {
        return try {
            val response =
                    apiClient.getClient().post("api/v1/bykc/courses/$courseId/sign") {
                        contentType(ContentType.Application.Json)
                        setBody(BykcSignRequest(courseId, lat, lng, signType))
                    }

            when (response.status) {
                HttpStatusCode.OK -> {
                    val successResponse = response.body<BykcSuccessResponse>()
                    Result.success(successResponse)
                }
                HttpStatusCode.Unauthorized -> {
                    val error = response.body<ApiErrorResponse>()
                    Result.failure(Exception(error.error.message))
                }
                else -> {
                    try {
                        val error = response.body<ApiErrorResponse>()
                        Result.failure(Exception(error.error.message))
                    } catch (e: Exception) {
                        Result.failure(Exception("签到/签退失败: ${response.status}"))
                    }
                }
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
