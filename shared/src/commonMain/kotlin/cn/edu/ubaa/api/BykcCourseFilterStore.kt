package cn.edu.ubaa.api

import com.russhwolf.settings.Settings
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class StoredBykcCourseFilters(
    val statuses: List<String> = emptyList(),
    val categories: List<String> = emptyList(),
    val campuses: List<String> = emptyList(),
)

object BykcCourseFilterStore {
  private const val KEY_PREFIX = "bykc_course_filters"
  private val json = Json { ignoreUnknownKeys = true }

  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun save(userKey: String, filters: StoredBykcCourseFilters) {
    settings.putString(storageKey(userKey), json.encodeToString(filters))
  }

  fun get(userKey: String): StoredBykcCourseFilters? {
    val raw = settings.getStringOrNull(storageKey(userKey)) ?: return null
    return runCatching { json.decodeFromString<StoredBykcCourseFilters>(raw) }.getOrNull()
  }

  fun clear(userKey: String) {
    settings.remove(storageKey(userKey))
  }

  private fun storageKey(userKey: String): String = "$KEY_PREFIX:$userKey"
}
