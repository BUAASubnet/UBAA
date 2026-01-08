package cn.edu.ubaa.api

import cn.edu.ubaa.BuildKonfig
import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * GitHub Release 信息 DTO。
 *
 * @property tagName 标签名（版本号）。
 * @property htmlUrl 发布页 URL。
 * @property body 发布说明内容。
 */
@Serializable
data class GitHubRelease(
  @SerialName("tag_name") val tagName: String,
  @SerialName("html_url") val htmlUrl: String,
  val body: String? = null,
)

/** 更新检测服务。 负责从 GitHub 检查是否有可用的新版本发布。 */
class UpdateService {
  private val client =
    HttpClient(getDefaultEngine()) {
      install(ContentNegotiation) {
        json(
          Json {
            ignoreUnknownKeys = true
            isLenient = true
          }
        )
      }
    }

  /**
   * 检查是否有新版本。 比较当前 [BuildKonfig.VERSION] 与 GitHub 上的最新版本。
   *
   * @return 如果有新版本则返回 [GitHubRelease]，否则返回 null。
   */
  suspend fun checkUpdate(): GitHubRelease? {
    return try {
      val latestRelease: GitHubRelease =
        client.get("https://api.botium.cn/github/repos/BUAASubnet/UBAA/releases/latest").body()
      val currentVersion = BuildKonfig.VERSION

      println("UpdateCheck: Latest=${latestRelease.tagName}, Current=$currentVersion")

      if (isNewerVersion(latestRelease.tagName, currentVersion)) {
        latestRelease
      } else {
        null
      }
    } catch (e: Exception) {
      null
    }
  }

  /**
   * 比较两个版本号字符串。
   *
   * @param latest 最新版本字符串。
   * @param current 当前版本字符串。
   * @return 是否为更新的版本。
   */
  private fun isNewerVersion(latest: String, current: String): Boolean {
    val latestClean = latest.trim().removePrefix("v").split("-")[0].trim()
    val currentClean = current.trim().removePrefix("v").split("-")[0].trim()

    if (latestClean == currentClean) return false

    val latestParts = latestClean.split(".").mapNotNull { it.toIntOrNull() }
    val currentParts = currentClean.split(".").mapNotNull { it.toIntOrNull() }

    val maxLength = maxOf(latestParts.size, currentParts.size)
    for (i in 0 until maxLength) {
      val latestPart = latestParts.getOrElse(i) { 0 }
      val currentPart = currentParts.getOrElse(i) { 0 }
      if (latestPart > currentPart) return true
      if (latestPart < currentPart) return false
    }

    return false
  }
}
