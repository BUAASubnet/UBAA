package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import io.ktor.client.request.*

interface ClassroomApiBackend {
  suspend fun queryClassrooms(xqid: Int, date: String): Result<ClassroomQueryResponse>
}

/** 教室查询相关 API。 用于查询指定校区和日期的空闲教室分布情况。 */
open class ClassroomApi(
    private val backendProvider: () -> ClassroomApiBackend = { ConnectionRuntime.apiFactory().classroomApi() }
) {
  internal constructor(backend: ClassroomApiBackend) : this({ backend })

  constructor(apiClient: ApiClient) : this({ RelayClassroomApiBackend(apiClient) })

  private fun currentBackend(): ClassroomApiBackend = backendProvider()

  /**
   * 查询空闲教室列表。
   *
   * @param xqid 校区 ID（如 1:学院路, 2:沙河, 3:杭州）。
   * @param date 查询日期（yyyy-MM-dd）。
   * @return 包含各楼层教室空闲情况的响应体。
   */
  open suspend fun queryClassrooms(xqid: Int, date: String): Result<ClassroomQueryResponse> {
    return currentBackend().queryClassrooms(xqid, date)
  }
}

internal class RelayClassroomApiBackend(
    private val apiClient: ApiClient = ApiClientProvider.shared
) : ClassroomApiBackend {
  override suspend fun queryClassrooms(xqid: Int, date: String): Result<ClassroomQueryResponse> {
    return safeApiCall {
      apiClient.getClient().get("api/v1/classroom/query") {
        parameter("xqid", xqid)
        parameter("date", date)
      }
    }
  }
}
