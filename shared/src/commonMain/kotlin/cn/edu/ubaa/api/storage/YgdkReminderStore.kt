package cn.edu.ubaa.api.storage

import com.russhwolf.settings.Settings

object YgdkReminderStore {
  private const val KEY_ENABLED_PREFIX = "ygdk_home_reminder_enabled"
  private const val KEY_WEEK_DONE_PREFIX = "ygdk_home_reminder_week_done"
  private const val KEY_TERM_DONE_PREFIX = "ygdk_home_reminder_term_done"

  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun isEnabled(userKey: String): Boolean =
      settings.getBoolean(enabledKey(userKey), defaultValue = true)

  fun setEnabled(userKey: String, enabled: Boolean) {
    settings.putBoolean(enabledKey(userKey), enabled)
  }

  fun isWeekDone(userKey: String, weekKey: String): Boolean =
      settings.getStringOrNull(weekDoneKey(userKey)) == weekKey

  fun markWeekDone(userKey: String, weekKey: String) {
    settings.putString(weekDoneKey(userKey), weekKey)
  }

  fun clearWeekDone(userKey: String) {
    settings.remove(weekDoneKey(userKey))
  }

  fun isTermDone(userKey: String, termKey: String): Boolean =
      settings.getStringOrNull(termDoneKey(userKey)) == termKey

  fun markTermDone(userKey: String, termKey: String) {
    settings.putString(termDoneKey(userKey), termKey)
  }

  fun clearTermDone(userKey: String) {
    settings.remove(termDoneKey(userKey))
  }

  fun clear(userKey: String) {
    settings.remove(enabledKey(userKey))
    clearWeekDone(userKey)
    clearTermDone(userKey)
  }

  private fun enabledKey(userKey: String): String = "$KEY_ENABLED_PREFIX:$userKey"

  private fun weekDoneKey(userKey: String): String = "$KEY_WEEK_DONE_PREFIX:$userKey"

  private fun termDoneKey(userKey: String): String = "$KEY_TERM_DONE_PREFIX:$userKey"
}
