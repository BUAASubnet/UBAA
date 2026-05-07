package cn.edu.ubaa.announcement

import cn.edu.ubaa.api.auth.AppAnnouncement
import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

interface AnnouncementProvider {
  fun currentAnnouncement(): AppAnnouncement?
}

class AnnouncementService(private val configFile: File = File("announcement.json")) :
    AnnouncementProvider {
  private val json = Json {
    ignoreUnknownKeys = true
    isLenient = true
  }

  override fun currentAnnouncement(): AppAnnouncement? {
    if (!configFile.exists() || !configFile.isFile) {
      return null
    }

    val config =
        runCatching { json.decodeFromString<AnnouncementConfig>(configFile.readText()) }
            .onFailure { error ->
              log.warn("Failed to read announcement config from {}", configFile.path, error)
            }
            .getOrNull() ?: return null

    return config.toAnnouncementOrNull()
  }

  private fun AnnouncementConfig.toAnnouncementOrNull(): AppAnnouncement? {
    if (!enabled) return null
    val normalizedId = id?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val normalizedTitle = title?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val normalizedContent = content?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return AppAnnouncement(
        id = normalizedId,
        title = normalizedTitle,
        content = normalizedContent,
        confirmText = confirmText?.trim()?.takeIf { it.isNotEmpty() },
        linkUrl = linkUrl?.trim()?.takeIf { it.isNotEmpty() },
    )
  }

  @Serializable
  private data class AnnouncementConfig(
      val enabled: Boolean = false,
      val id: String? = null,
      val title: String? = null,
      val content: String? = null,
      val confirmText: String? = null,
      val linkUrl: String? = null,
  )

  private companion object {
    private val log = LoggerFactory.getLogger(AnnouncementService::class.java)
  }
}
