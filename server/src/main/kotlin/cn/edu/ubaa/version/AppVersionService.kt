package cn.edu.ubaa.version

import cn.edu.ubaa.api.AppVersionCheckResponse
import io.github.cdimascio.dotenv.dotenv
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import java.io.File
import java.util.Properties
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

data class AppVersionRuntimeConfig(
    val serverVersion: String,
    val downloadUrl: String,
) {
  companion object {
    private const val FALLBACK_DOWNLOAD_URL = "https://github.com/BUAASubnet/UBAA/releases"
    private const val UNKNOWN_SERVER_VERSION = "unknown"

    fun load(): AppVersionRuntimeConfig =
        AppVersionRuntimeConfig(
            serverVersion = loadServerVersion(),
            downloadUrl =
                resolveDownloadUrl(
                    dotenv { ignoreIfMissing = true }["UPDATE_DOWNLOAD_URL"]
                        ?: System.getenv("UPDATE_DOWNLOAD_URL")
                ),
        )

    internal fun loadServerVersion(): String {
      loadVersionFromSystemProperty()?.let {
        return it
      }
      loadVersionFromEnvironment()?.let {
        return it
      }
      loadVersionFromEmbeddedResource()?.let {
        return it
      }
      loadVersionFromGradlePropertiesFile()?.let {
        return it
      }
      return UNKNOWN_SERVER_VERSION
    }

    private fun loadVersionFromSystemProperty(): String? =
        System.getProperty("ubaa.server.version")?.trim()?.takeIf {
          it.isNotEmpty() && it != UNKNOWN_SERVER_VERSION
        }

    private fun loadVersionFromEnvironment(): String? =
        System.getenv("UBAA_SERVER_VERSION")?.trim()?.takeIf {
          it.isNotEmpty() && it != UNKNOWN_SERVER_VERSION
        }

    private fun loadVersionFromEmbeddedResource(): String? = loadVersionFromManifest()

    private fun loadVersionFromManifest(): String? =
        AppVersionRuntimeConfig::class.java.`package`?.implementationVersion
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

    private fun loadVersionFromGradlePropertiesFile(): String? {
      val gradleProperties = File("gradle.properties")
      if (!gradleProperties.exists()) {
        return null
      }

      val properties = Properties()
      gradleProperties.inputStream().use { properties.load(it) }
      return properties.getProperty("project.version")?.trim()?.takeIf { it.isNotEmpty() }
    }

    internal fun resolveDownloadUrl(configuredUrl: String?): String =
        configuredUrl?.trim()?.takeIf { it.isNotEmpty() } ?: FALLBACK_DOWNLOAD_URL

    internal fun isKnownServerVersion(version: String): Boolean =
        version.trim().isNotEmpty() && version.trim() != UNKNOWN_SERVER_VERSION
  }
}

interface ReleaseNotesFetcher {
  suspend fun fetchReleaseNotes(serverVersion: String): String?

  fun close() {}
}

internal class ProxyReleaseNotesFetcher(
    private val client: HttpClient = defaultClient(),
    private val releasesBaseUrl: String = RELEASES_PROXY_BASE_URL,
) : ReleaseNotesFetcher {

  override suspend fun fetchReleaseNotes(serverVersion: String): String? {
    for (tag in tagCandidates(serverVersion)) {
      val response =
          runCatching { client.get("$releasesBaseUrl/tags/$tag") }.getOrNull() ?: continue
      if (response.status != HttpStatusCode.OK) continue

      val release = runCatching { response.body<ReleaseProxyResponse>() }.getOrNull() ?: continue
      return release.body?.trim()?.ifBlank { null }
    }
    return null
  }

  override fun close() {
    client.close()
  }

  private fun tagCandidates(serverVersion: String): List<String> {
    val normalizedVersion = AppVersionService.normalizeVersion(serverVersion)
    return listOf("v$normalizedVersion", normalizedVersion).distinct()
  }

  @Serializable private data class ReleaseProxyResponse(val body: String? = null)

  companion object {
    private const val RELEASES_PROXY_BASE_URL =
        "https://api.botium.cn/github/repos/BUAASubnet/UBAA/releases"

    private fun defaultClient(): HttpClient =
        HttpClient(CIO) {
          install(ContentNegotiation) {
            json(
                Json {
                  ignoreUnknownKeys = true
                  isLenient = true
                }
            )
          }
        }
  }
}

class AppVersionService(
    private val config: AppVersionRuntimeConfig = AppVersionRuntimeConfig.load(),
    private val releaseNotesFetcher: ReleaseNotesFetcher = ProxyReleaseNotesFetcher(),
) {
  @Volatile private var closed = false
  private val releaseNotesCacheMutex = Mutex()
  private var cachedReleaseNotesVersion: String? = null
  private var cachedReleaseNotes: String? = null
  private var releaseNotesCacheInitialized = false

  suspend fun checkVersion(clientVersion: String): AppVersionCheckResponse {
    val aligned =
        !AppVersionRuntimeConfig.isKnownServerVersion(config.serverVersion) ||
            normalizeVersion(clientVersion) == normalizeVersion(config.serverVersion)
    val releaseNotes = if (aligned) null else loadReleaseNotes(config.serverVersion)

    return AppVersionCheckResponse(
        serverVersion = config.serverVersion,
        aligned = aligned,
        downloadUrl = config.downloadUrl,
        releaseNotes = releaseNotes,
    )
  }

  fun close() {
    if (closed) return
    closed = true
    releaseNotesFetcher.close()
  }

  internal fun isClosed(): Boolean = closed

  private suspend fun loadReleaseNotes(serverVersion: String): String? {
    val normalizedVersion = normalizeVersion(serverVersion)
    return releaseNotesCacheMutex.withLock {
      if (releaseNotesCacheInitialized && cachedReleaseNotesVersion == normalizedVersion) {
        return@withLock cachedReleaseNotes
      }

      val releaseNotes = releaseNotesFetcher.fetchReleaseNotes(serverVersion)
      cachedReleaseNotesVersion = normalizedVersion
      cachedReleaseNotes = releaseNotes
      releaseNotesCacheInitialized = true
      releaseNotes
    }
  }

  companion object {
    internal fun normalizeVersion(version: String): String = version.trim().removePrefix("v")
  }
}

object GlobalAppVersionService {
  @Volatile private var current: AppVersionService? = null

  val instance: AppVersionService
    get() {
      current
          ?.takeUnless { it.isClosed() }
          ?.let {
            return it
          }
      return synchronized(this) {
        current?.takeUnless { it.isClosed() } ?: AppVersionService().also { current = it }
      }
    }

  fun close() {
    synchronized(this) {
      current?.close()
      current = null
    }
  }

  fun release(service: AppVersionService) {
    synchronized(this) {
      if (current === service) {
        current?.close()
        current = null
      } else {
        service.close()
      }
    }
  }
}
