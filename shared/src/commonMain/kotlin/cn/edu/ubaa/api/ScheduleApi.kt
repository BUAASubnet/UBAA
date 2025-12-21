package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.request.*

/** Schedule service for fetching course schedules */
class ScheduleApi(private val apiClient: ApiClient = ApiClientProvider.shared) {

    suspend fun getTerms(): Result<List<Term>> {
        return safeApiCall { apiClient.getClient().get("api/v1/schedule/terms") }
    }

    suspend fun getWeeks(termCode: String): Result<List<Week>> {
        return safeApiCall { 
            apiClient.getClient().get("api/v1/schedule/weeks") {
                parameter("termCode", termCode)
            }
        }
    }

    suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> {
        return safeApiCall {
            apiClient.getClient().get("api/v1/schedule/week") {
                parameter("termCode", termCode)
                parameter("week", week)
            }
        }
    }

    suspend fun getTodaySchedule(): Result<List<TodayClass>> {
        return safeApiCall { apiClient.getClient().get("api/v1/schedule/today") }
    }

    suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData> {
        return safeApiCall {
            apiClient.getClient().get("api/v1/exam/list") {
                parameter("termCode", termCode)
            }
        }
    }
}
