package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.SpocAssignmentDetailDto
import cn.edu.ubaa.model.dto.SpocAssignmentsResponse
import io.ktor.client.request.get

interface SpocApiBackend {
  suspend fun getAssignments(): Result<SpocAssignmentsResponse>

  suspend fun getAssignmentDetail(assignmentId: String): Result<SpocAssignmentDetailDto>
}

/** SPOC 作业查询 API。 */
open class SpocApi(
    private val backendProvider: () -> SpocApiBackend = { ConnectionRuntime.apiFactory().spocApi() }
) {
  internal constructor(backend: SpocApiBackend) : this({ backend })

  constructor(apiClient: ApiClient) : this({ RelaySpocApiBackend(apiClient) })

  private fun currentBackend(): SpocApiBackend = backendProvider()

  /** 获取当前默认学期的所有作业摘要。 */
  open suspend fun getAssignments(): Result<SpocAssignmentsResponse> {
    return currentBackend().getAssignments()
  }

  /** 获取指定作业的详细信息。 */
  open suspend fun getAssignmentDetail(assignmentId: String): Result<SpocAssignmentDetailDto> {
    return currentBackend().getAssignmentDetail(assignmentId)
  }
}

internal class RelaySpocApiBackend(private val apiClient: ApiClient = ApiClientProvider.shared) :
    SpocApiBackend {
  override suspend fun getAssignments(): Result<SpocAssignmentsResponse> {
    return safeApiCall { apiClient.getClient().get("api/v1/spoc/assignments") }
  }

  override suspend fun getAssignmentDetail(assignmentId: String): Result<SpocAssignmentDetailDto> {
    return safeApiCall { apiClient.getClient().get("api/v1/spoc/assignments/$assignmentId") }
  }
}
