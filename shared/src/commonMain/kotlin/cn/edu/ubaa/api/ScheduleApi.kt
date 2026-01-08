package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.request.*

/**
 * 课程表与考试查询服务。 负责从后端获取学期、周次、课表安排以及考试安排等信息。
 *
 * @param apiClient 使用的 ApiClient 实例。
 */
class ScheduleApi(private val apiClient: ApiClient = ApiClientProvider.shared) {

  /**
   * 获取所有可用学期列表。
   *
   * @return 学期信息列表。
   */
  suspend fun getTerms(): Result<List<Term>> {
    return safeApiCall { apiClient.getClient().get("api/v1/schedule/terms") }
  }

  /**
   * 获取指定学期对应的所有教学周。
   *
   * @param termCode 学期代码（如 "2024-2025-1"）。
   * @return 该学期的教学周列表。
   */
  suspend fun getWeeks(termCode: String): Result<List<Week>> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/schedule/weeks") { parameter("termCode", termCode) }
    }
  }

  /**
   * 获取指定学期和周次的个人课程表。
   *
   * @param termCode 学期代码。
   * @param week 周次序号。
   * @return 包含该周所有排课信息的 WeeklySchedule。
   */
  suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/schedule/week") {
        parameter("termCode", termCode)
        parameter("week", week)
      }
    }
  }

  /**
   * 获取今日课程安排摘要。
   *
   * @return 今日课程列表。
   */
  suspend fun getTodaySchedule(): Result<List<TodayClass>> {
    return safeApiCall { apiClient.getClient().get("api/v1/schedule/today") }
  }

  /**
   * 获取指定学期的考试安排。
   *
   * @param termCode 学期代码。
   * @return 包含学生信息、已安排考试和未安排考试的数据汇总。
   */
  suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/exam/list") { parameter("termCode", termCode) }
    }
  }
}
