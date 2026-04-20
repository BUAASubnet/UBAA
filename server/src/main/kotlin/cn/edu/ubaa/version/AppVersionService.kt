package cn.edu.ubaa.version

import cn.edu.ubaa.api.AppVersionCheckResponse
import cn.edu.ubaa.api.AppUpdateStatus
import cn.edu.ubaa.metrics.AppObservability
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
    val latestVersion: String,
    val downloadUrl: String,
) {
  companion object {
    private const val FALLBACK_DOWNLOAD_URL = "https://github.com/BUAASubnet/UBAA/releases"
    private const val UNKNOWN_SERVER_VERSION = "unknown"

    fun load(): AppVersionRuntimeConfig =
        AppVersionRuntimeConfig(
            latestVersion = loadServerVersion(),
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
        AppVersionRuntimeConfig::class.java.`package`?.implementationVersion?.trim()?.takeIf {
          it.isNotEmpty()
        }

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
  suspend fun fetchReleaseNotes(latestVersion: String): String?

  fun close() {}
}

internal class ProxyReleaseNotesFetcher(
    private val client: HttpClient = defaultClient(),
    private val releasesBaseUrl: String = RELEASES_PROXY_BASE_URL,
) : ReleaseNotesFetcher {

  override suspend fun fetchReleaseNotes(latestVersion: String): String? {
    for (tag in tagCandidates(latestVersion)) {
      val response =
          runCatching {
                AppObservability.observeUpstreamRequest("release_proxy", "fetch_release_notes") {
                  client.get("$releasesBaseUrl/tags/$tag")
                }
              }
              .getOrNull() ?: continue
      if (response.status != HttpStatusCode.OK) continue

      val release = runCatching { response.body<ReleaseProxyResponse>() }.getOrNull() ?: continue
      return release.body?.trim()?.ifBlank { null }
    }
    return null
  }

  override fun close() {
    client.close()
  }

  private fun tagCandidates(latestVersion: String): List<String> {
    val normalizedVersion = AppVersionService.normalizeVersion(latestVersion)
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
    val status =
        when {
          !AppVersionRuntimeConfig.isKnownServerVersion(config.latestVersion) ->
              AppUpdateStatus.UNKNOWN_LATEST_VERSION
          compareVersions(clientVersion, config.latestVersion) < 0 ->
              AppUpdateStatus.UPDATE_AVAILABLE
          else -> AppUpdateStatus.UP_TO_DATE
        }
    val updateAvailable = status == AppUpdateStatus.UPDATE_AVAILABLE
    val releaseNotes = if (updateAvailable) loadReleaseNotes(config.latestVersion) else null

    return AppVersionCheckResponse(
        latestVersion = config.latestVersion,
        status = status,
        updateAvailable = updateAvailable,
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

  private suspend fun loadReleaseNotes(latestVersion: String): String? {
    val normalizedVersion = normalizeVersion(latestVersion)
    return releaseNotesCacheMutex.withLock {
      if (releaseNotesCacheInitialized && cachedReleaseNotesVersion == normalizedVersion) {
        return@withLock cachedReleaseNotes
      }

      val releaseNotes = releaseNotesFetcher.fetchReleaseNotes(latestVersion)
      cachedReleaseNotesVersion = normalizedVersion
      cachedReleaseNotes = releaseNotes
      releaseNotesCacheInitialized = true
      releaseNotes
    }
  }

  companion object {
    internal fun normalizeVersion(version: String): String = version.trim().removePrefix("v")

    internal fun compareVersions(left: String, right: String): Int {
      val leftParts = normalizeVersion(left).split('.').map { it.toIntOrNull() ?: 0 }
      val rightParts = normalizeVersion(right).split('.').map { it.toIntOrNull() ?: 0 }
      val size = maxOf(leftParts.size, rightParts.size)
      for (index in 0 until size) {
        val leftValue = leftParts.getOrElse(index) { 0 }
        val rightValue = rightParts.getOrElse(index) { 0 }
        if (leftValue != rightValue) {
          return leftValue.compareTo(rightValue)
        }
      }
      return 0
    }
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
