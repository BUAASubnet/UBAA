package cn.edu.ubaa.api.storage

import cn.edu.ubaa.api.ConnectionMode
import cn.edu.ubaa.api.ConnectionModeStore
import com.russhwolf.settings.Settings
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class StoredGradeScoreCache(
    val termCode: String,
    val termName: String? = null,
    val scores: List<StoredGradeScoreEntry> = emptyList(),
)

@Serializable
data class StoredGradeScoreEntry(
    val key: String,
    val courseName: String? = null,
    val courseCode: String? = null,
    val score: String? = null,
)

object GradeScoreCacheStore {
  private const val KEY_PREFIX = "grade_score_cache"
  private const val KEY_USER_INDEX = "grade_score_cache_users"
  private val json = Json { ignoreUnknownKeys = true }

  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun save(userKey: String, cache: StoredGradeScoreCache) {
    addUserKey(userKey)
    settings.putString(storageKey(userKey), json.encodeToString(cache))
  }

  fun get(userKey: String): StoredGradeScoreCache? {
    val raw = settings.getStringOrNull(storageKey(userKey)) ?: return null
    return runCatching { json.decodeFromString<StoredGradeScoreCache>(raw) }.getOrNull()
  }

  fun clear(userKey: String) {
    settings.remove(storageKey(userKey))
  }

  fun clearAllScopes() {
    loadUserKeys().forEach { userKey ->
      ConnectionMode.entries.forEach { mode -> settings.remove(storageKey(userKey, mode)) }
    }
    settings.remove(KEY_USER_INDEX)
  }

  fun clearKnownUserAllModes(userKey: String) {
    ConnectionMode.entries.forEach { mode -> settings.remove(storageKey(userKey, mode)) }
  }

  private fun storageKey(
      userKey: String,
      mode: ConnectionMode? = ConnectionModeStore.get(),
  ): String {
    val effectiveMode = mode ?: ConnectionMode.SERVER_RELAY
    return "$KEY_PREFIX:${effectiveMode.storageKey}:$userKey"
  }

  private fun addUserKey(userKey: String) {
    val keys = loadUserKeys()
    if (userKey in keys) return
    settings.putString(KEY_USER_INDEX, json.encodeToString(keys + userKey))
  }

  private fun loadUserKeys(): List<String> {
    val raw = settings.getStringOrNull(KEY_USER_INDEX) ?: return emptyList()
    return runCatching { json.decodeFromString<List<String>>(raw) }.getOrDefault(emptyList())
  }
}
