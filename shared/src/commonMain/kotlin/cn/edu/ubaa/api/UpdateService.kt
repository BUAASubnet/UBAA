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
