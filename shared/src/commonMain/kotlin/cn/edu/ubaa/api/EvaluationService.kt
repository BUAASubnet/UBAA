package cn.edu.ubaa.api

import cn.edu.ubaa.model.evaluation.EvaluationCourse
import cn.edu.ubaa.model.evaluation.EvaluationCoursesResponse
import cn.edu.ubaa.model.evaluation.EvaluationResult
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType

interface EvaluationServiceBackend {
  suspend fun getAllEvaluations(): Result<EvaluationCoursesResponse>

  suspend fun submitEvaluations(courses: List<EvaluationCourse>): List<EvaluationResult>
}

class EvaluationService(
    private val backendProvider: () -> EvaluationServiceBackend = {
      ConnectionRuntime.apiFactory().evaluationService()
    }
) {
  internal constructor(backend: EvaluationServiceBackend) : this({ backend })

  constructor(apiClient: ApiClient) : this({ RelayEvaluationServiceBackend(apiClient) })

  private fun currentBackend(): EvaluationServiceBackend = backendProvider()

  /** 获取所有评教课程（包括已评教和未评教），附带进度信息。 */
  suspend fun getAllEvaluations(): Result<EvaluationCoursesResponse> {
    return currentBackend().getAllEvaluations()
  }

  /**
   * 获取待评教课程列表（仅未评教课程）。
   *
   * @deprecated 使用 getAllEvaluations() 获取完整信息。
   */
  suspend fun getPendingEvaluations(): Result<List<EvaluationCourse>> {
    return getAllEvaluations().map { response -> response.courses.filter { !it.isEvaluated } }
  }

  suspend fun submitEvaluations(courses: List<EvaluationCourse>): List<EvaluationResult> {
    return currentBackend().submitEvaluations(courses)
  }
}

internal class RelayEvaluationServiceBackend(
    private val apiClient: ApiClient = ApiClientProvider.shared
) : EvaluationServiceBackend {
  override suspend fun getAllEvaluations(): Result<EvaluationCoursesResponse> {
    return safeApiCall { apiClient.getClient().get("/api/v1/evaluation/list") }
  }

  override suspend fun submitEvaluations(courses: List<EvaluationCourse>): List<EvaluationResult> {
    return try {
      apiClient
          .getClient()
          .post("/api/v1/evaluation/submit") {
            contentType(ContentType.Application.Json)
            setBody(courses)
          }
          .body()
    } catch (e: Exception) {
      val message = e.toUserFacingApiException("评教提交失败，请稍后重试").message ?: "评教提交失败，请稍后重试"
      courses.map { EvaluationResult(false, message, it.kcmc) }
    }
  }
}
