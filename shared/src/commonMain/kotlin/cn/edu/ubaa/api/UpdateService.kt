package cn.edu.ubaa.api

import cn.edu.ubaa.BuildKonfig
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*
import kotlinx.serialization.Serializable

@Serializable
enum class AppUpdateStatus {
  UP_TO_DATE,
  UPDATE_AVAILABLE,
  UNKNOWN_LATEST_VERSION,
}

@Serializable
data class AppVersionCheckResponse(
    val latestVersion: String,
    val status: AppUpdateStatus,
    val updateAvailable: Boolean,
    val downloadUrl: String,
    val releaseNotes: String? = null,
    val serverVersion: String? = null,
    val aligned: Boolean? = null,
)

/** 更新检测服务。 固定通过 relay 服务端检查客户端是否存在新版本。 */
class UpdateService(private val apiClientProvider: () -> ApiClient = { ApiClientProvider.shared }) {
  constructor(apiClient: ApiClient) : this({ apiClient })

  /** 检查当前客户端是否需要更新。 */
  suspend fun checkUpdate(clientVersion: String = BuildKonfig.VERSION): AppVersionCheckResponse? {
    return try {
      val apiClient = apiClientProvider()
      val response =
          apiClient.getClient().get("api/v1/app/version") {
            parameter("clientVersion", clientVersion)
          }
      if (response.status != HttpStatusCode.OK) {
        return null
      }
      response.body<AppVersionCheckResponse>().takeIf {
        it.status == AppUpdateStatus.UPDATE_AVAILABLE
      }
    } catch (e: Exception) {
      null
    }
  }
}
