package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.*
import io.ktor.client.request.*

interface ApiService {
    suspend fun getTerms(): Result<List<Term>>
    suspend fun getWeeks(termCode: String): Result<List<Week>>
    suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule>
    suspend fun getTodaySchedule(): Result<List<TodayClass>>
    suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData>
    
    // 博雅课程
    suspend fun getBykcProfile(): Result<BykcUserProfileDto>
    suspend fun getBykcCourses(page: Int = 1, pageSize: Int = 20, all: Boolean = false): Result<List<BykcCourseDto>>
    suspend fun getBykcCourseDetail(id: Int): Result<BykcCourseDetailDto>
    suspend fun getBykcChosenCourses(): Result<List<BykcChosenCourseDto>>
    suspend fun getBykcStatistics(): Result<BykcStatisticsDto>
    suspend fun selectBykcCourse(courseId: Int): Result<Unit>
    suspend fun unselectBykcCourse(courseId: Int): Result<Unit>
}

class ApiServiceImpl(private val apiClient: ApiClient) : ApiService {
    
    override suspend fun getTerms(): Result<List<Term>> = safeApiCall {
        apiClient.getClient().get("api/v1/schedule/terms")
    }

    override suspend fun getWeeks(termCode: String): Result<List<Week>> = safeApiCall {
        apiClient.getClient().get("api/v1/schedule/weeks") {
            parameter("termCode", termCode)
        }
    }

    override suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> = safeApiCall {
        apiClient.getClient().get("api/v1/schedule/week") {
            parameter("termCode", termCode)
            parameter("week", week)
        }
    }
    
    override suspend fun getTodaySchedule(): Result<List<TodayClass>> = safeApiCall {
        apiClient.getClient().get("api/v1/schedule/today")
    }

    override suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData> = safeApiCall {
        apiClient.getClient().get("api/v1/exam/list") {
            parameter("termCode", termCode)
        }
    }

    override suspend fun getBykcProfile(): Result<BykcUserProfileDto> = safeApiCall {
        apiClient.getClient().get("api/v1/bykc/profile")
    }

    override suspend fun getBykcCourses(page: Int, pageSize: Int, all: Boolean): Result<List<BykcCourseDto>> = runCatching {
        // 因需手动提取响应体中的 courses 列表，此处暂不使用 safeApiCall
        // 后续可为 Result 添加 map 扩展函数来优化
        apiClient.getClient().get("api/v1/bykc/courses") {
            parameter("page", page)
            parameter("size", pageSize)
            parameter("all", all)
        }.body<BykcCoursesResponse>().courses
    }

    override suspend fun getBykcCourseDetail(id: Int): Result<BykcCourseDetailDto> = safeApiCall {
        apiClient.getClient().get("api/v1/bykc/courses/$id")
    }

    override suspend fun getBykcChosenCourses(): Result<List<BykcChosenCourseDto>> = safeApiCall {
        apiClient.getClient().get("api/v1/bykc/courses/chosen")
    }

    override suspend fun getBykcStatistics(): Result<BykcStatisticsDto> = safeApiCall {
        apiClient.getClient().get("api/v1/bykc/statistics")
    }

    override suspend fun selectBykcCourse(courseId: Int): Result<Unit> = safeApiCall {
        apiClient.getClient().post("api/v1/bykc/courses/$courseId/select")
    }

    override suspend fun unselectBykcCourse(courseId: Int): Result<Unit> = safeApiCall {
        apiClient.getClient().delete("api/v1/bykc/courses/$courseId/select")
    }
}
