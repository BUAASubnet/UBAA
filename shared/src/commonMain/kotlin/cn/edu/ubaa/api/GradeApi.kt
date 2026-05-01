package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.GradeData
import io.ktor.client.request.get
import io.ktor.client.request.parameter

interface GradeApiBackend {
  suspend fun getGrades(termCode: String): Result<GradeData>
}

class GradeApi(
    private val backendProvider: () -> GradeApiBackend = {
      ConnectionRuntime.apiFactory().gradeApi()
    }
) {
  internal constructor(backend: GradeApiBackend) : this({ backend })

  constructor(apiClient: ApiClient) : this({ RelayGradeApiBackend(apiClient) })

  private fun currentBackend(): GradeApiBackend = backendProvider()

  suspend fun getGrades(termCode: String): Result<GradeData> = currentBackend().getGrades(termCode)
}

internal class RelayGradeApiBackend(private val apiClient: ApiClient = ApiClientProvider.shared) :
    GradeApiBackend {
  override suspend fun getGrades(termCode: String): Result<GradeData> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/grade/list") { parameter("termCode", termCode) }
    }
  }
}
