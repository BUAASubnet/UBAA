package cn.edu.ubaa.api.storage

import com.russhwolf.settings.Settings

object AnnouncementReadStore {
  private const val KEY_PREFIX = "announcement_read"

  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun isRead(id: String): Boolean {
    val normalizedId = id.trim().takeIf { it.isNotEmpty() } ?: return false
    return settings.getBoolean(key(normalizedId), false)
  }

  fun markRead(id: String) {
    val normalizedId = id.trim().takeIf { it.isNotEmpty() } ?: return
    settings.putBoolean(key(normalizedId), true)
  }

  private fun key(id: String): String = "$KEY_PREFIX:$id"
}
