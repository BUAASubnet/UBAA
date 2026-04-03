package cn.edu.ubaa.api

import cn.edu.ubaa.BuildKonfig
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*
import kotlinx.serialization.Serializable

@Serializable
data class AppVersionCheckResponse(
    val serverVersion: String,
    val aligned: Boolean,
    val downloadUrl: String,
    val releaseNotes: String? = null,
)

/** 更新检测服务。 负责通过服务端检查客户端与服务端版本是否对齐。 */
class UpdateService(private val apiClient: ApiClient = ApiClientProvider.shared) {

  /** 检查当前客户端是否需要更新。 */
  suspend fun checkUpdate(clientVersion: String = BuildKonfig.VERSION): AppVersionCheckResponse? {
    return try {
      val response =
          apiClient.getClient().get("api/v1/app/version") { parameter("clientVersion", clientVersion) }
      if (response.status != HttpStatusCode.OK) {
        return null
      }
      response.body<AppVersionCheckResponse>().takeUnless { it.aligned }
    } catch (e: Exception) {
      null
    }
  }
}
