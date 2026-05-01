package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentsResponse
import io.ktor.client.request.get

interface JudgeApiBackend {
  suspend fun getAssignments(): Result<JudgeAssignmentsResponse>

  suspend fun getAssignmentDetail(
      courseId: String,
      assignmentId: String,
  ): Result<JudgeAssignmentDetailDto>
}

/** 希冀作业查询 API。 */
open class JudgeApi(
    private val backendProvider: () -> JudgeApiBackend = { ConnectionRuntime.apiFactory().judgeApi() }
) {
  internal constructor(backend: JudgeApiBackend) : this({ backend })

  constructor(apiClient: ApiClient) : this({ RelayJudgeApiBackend(apiClient) })

  private fun currentBackend(): JudgeApiBackend = backendProvider()

  /** 获取所有课程下的希冀作业摘要。 */
  open suspend fun getAssignments(): Result<JudgeAssignmentsResponse> {
    return currentBackend().getAssignments()
  }

  /** 获取指定课程下的指定作业详情。 */
  open suspend fun getAssignmentDetail(
      courseId: String,
      assignmentId: String,
  ): Result<JudgeAssignmentDetailDto> {
    return currentBackend().getAssignmentDetail(courseId, assignmentId)
  }
}

internal class RelayJudgeApiBackend(private val apiClient: ApiClient = ApiClientProvider.shared) :
    JudgeApiBackend {
  override suspend fun getAssignments(): Result<JudgeAssignmentsResponse> {
    return safeApiCall { apiClient.getClient().get("api/v1/judge/assignments") }
  }

  override suspend fun getAssignmentDetail(
      courseId: String,
      assignmentId: String,
  ): Result<JudgeAssignmentDetailDto> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/judge/courses/$courseId/assignments/$assignmentId")
    }
  }
}
