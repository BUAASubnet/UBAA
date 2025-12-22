package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import io.ktor.client.request.*

class ClassroomApi(private val apiClient: ApiClient = ApiClientProvider.shared) {
    suspend fun queryClassrooms(xqid: Int, date: String): Result<ClassroomQueryResponse> {
        return safeApiCall {
            apiClient.getClient().get("api/v1/classroom/query") {
                parameter("xqid", xqid)
                parameter("date", date)
            }
        }
    }
}
