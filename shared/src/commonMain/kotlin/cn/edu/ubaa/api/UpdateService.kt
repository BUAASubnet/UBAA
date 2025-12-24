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

@Serializable
data class GitHubRelease(
        @SerialName("tag_name") val tagName: String,
        @SerialName("html_url") val htmlUrl: String,
        val body: String? = null
)

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

    suspend fun checkUpdate(): GitHubRelease? {
        return try {
            val latestRelease: GitHubRelease =
                    client.get("https://api.botium.cn/github/repos/BUAASubnet/UBAA/releases/latest")
                            .body()
            val currentVersion = BuildKonfig.VERSION

            if (isNewerVersion(latestRelease.tagName, currentVersion)) {
                latestRelease
            } else {
                null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun isNewerVersion(latest: String, current: String): Boolean {
        val latestClean = latest.removePrefix("v").split("-")[0]
        val currentClean = current.removePrefix("v").split("-")[0]

        val latestParts = latestClean.split(".").mapNotNull { it.toIntOrNull() }
        val currentParts = currentClean.split(".").mapNotNull { it.toIntOrNull() }

        for (i in 0 until minOf(latestParts.size, currentParts.size)) {
            if (latestParts[i] > currentParts[i]) return true
            if (latestParts[i] < currentParts[i]) return false
        }

        return latestParts.size > currentParts.size
    }
}
