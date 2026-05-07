package cn.edu.ubaa.api.auth

import cn.edu.ubaa.api.core.ApiClient
import io.ktor.client.call.body
import io.ktor.client.request.get
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable

@Serializable
data class AppAnnouncement(
    val id: String,
    val title: String,
    val content: String,
    val confirmText: String? = null,
    val linkUrl: String? = null,
)

/** 公告检测服务。固定通过 relay 服务端读取当前公告配置。 */
class AnnouncementService(
    private val apiClientProvider: () -> ApiClient = { ApiClientProvider.shared }
) {
  constructor(apiClient: ApiClient) : this({ apiClient })

  suspend fun checkAnnouncement(): AppAnnouncement? {
    return try {
      val response = apiClientProvider().getClient().get("api/v1/app/announcement")
      if (response.status != HttpStatusCode.OK) {
        return null
      }
      response.body<AppAnnouncement>()
    } catch (e: Throwable) {
      if (e is CancellationException) throw e
      null
    }
  }
}
