package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import io.ktor.client.call.*
import io.ktor.client.request.*

/** 核心 API 服务接口，定义了应用所需的主要数据获取契约。 整合了课表、考试、博雅课程等核心业务功能。 */
interface ApiService {
  /**
   * 获取所有学期列表。
   *
   * @return 包含学期列表的 [Result]。若失败则包含异常信息。
   */
  suspend fun getTerms(): Result<List<Term>>

  /**
   * 获取指定学期的周次列表。
   *
   * @return 包含周次列表的 [Result]。若失败则包含异常信息。
   */
  suspend fun getWeeks(termCode: String): Result<List<Week>>

  /**
   * 获取指定周次的课程表。
   *
   * @return 包含周课表的 [Result]。若失败则包含异常信息。
   */
  suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule>

  /**
   * 获取今日课程摘要。
   *
   * @return 包含今日课程列表的 [Result]。若失败则包含异常信息。
   */
  suspend fun getTodaySchedule(): Result<List<TodayClass>>

  /**
   * 获取考试安排数据。
   *
   * @return 包含考试安排的 [Result]。若失败则包含异常信息。
   */
  suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData>

  /**
   * 获取博雅课程用户状态资料。
   *
   * @return 包含用户资料的 [Result]。若失败则包含异常信息。
   */
  suspend fun getBykcProfile(): Result<BykcUserProfileDto>

  /**
   * 分页查询博雅课程。
   *
   * @return 包含分页课程数据的 [Result]。若失败则包含异常信息。
   */
  suspend fun getBykcCourses(
    page: Int = 1,
    pageSize: Int = 20,
    all: Boolean = false,
  ): Result<BykcCoursesResponse>

  /**
   * 获取博雅课程详情。
   *
   * @return 包含课程详情的 [Result]。若失败则包含异常信息。
   */
  suspend fun getBykcCourseDetail(id: Int): Result<BykcCourseDetailDto>

  /**
   * 获取已选博雅课程列表。
   *
   * @return 包含已选课程列表的 [Result]。若失败则包含异常信息。
   */
  suspend fun getBykcChosenCourses(): Result<List<BykcChosenCourseDto>>

  /**
   * 获取博雅修读统计。
   *
   * @return 包含统计数据的 [Result]。若失败则包含异常信息。
   */
  suspend fun getBykcStatistics(): Result<BykcStatisticsDto>

  /**
   * 选择（报名）博雅课程。
   *
   * @return 包含操作结果的 [Result]。若失败则包含异常信息。
   */
  suspend fun selectBykcCourse(courseId: Int): Result<Unit>

  /**
   * 退选博雅课程。
   *
   * @return 包含操作结果的 [Result]。若失败则包含异常信息。
   */
  suspend fun unselectBykcCourse(courseId: Int): Result<Unit>
}

/** ApiService 的标准实现类，通过 ApiClient 与后端通信。 */
class ApiServiceImpl(private val apiClient: ApiClient) : ApiService {

  override suspend fun getTerms(): Result<List<Term>> = safeApiCall {
    apiClient.getClient().get("api/v1/schedule/terms")
  }

  override suspend fun getWeeks(termCode: String): Result<List<Week>> = safeApiCall {
    apiClient.getClient().get("api/v1/schedule/weeks") { parameter("termCode", termCode) }
  }

  override suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> =
    safeApiCall {
      apiClient.getClient().get("api/v1/schedule/week") {
        parameter("termCode", termCode)
        parameter("week", week)
      }
    }

  override suspend fun getTodaySchedule(): Result<List<TodayClass>> = safeApiCall {
    apiClient.getClient().get("api/v1/schedule/today")
  }

  override suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData> =
    safeApiCall {
      apiClient.getClient().get("api/v1/exam/list") { parameter("termCode", termCode) }
    }

  override suspend fun getBykcProfile(): Result<BykcUserProfileDto> = safeApiCall {
    apiClient.getClient().get("api/v1/bykc/profile")
  }

  override suspend fun getBykcCourses(
    page: Int,
    pageSize: Int,
    all: Boolean,
  ): Result<BykcCoursesResponse> = runCatching {
    apiClient
      .getClient()
      .get("api/v1/bykc/courses") {
        parameter("page", page)
        parameter("size", pageSize)
        parameter("all", all)
      }
      .body<BykcCoursesResponse>()
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
