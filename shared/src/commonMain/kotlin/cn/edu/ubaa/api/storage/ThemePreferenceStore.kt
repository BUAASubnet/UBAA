package cn.edu.ubaa.api.storage

import com.russhwolf.settings.Settings

data class StoredThemePreferences(
    val themeMode: String = ThemePreferenceStore.DEFAULT_THEME_MODE,
    val seedColorValue: Long = ThemePreferenceStore.DEFAULT_SEED_COLOR_VALUE,
    val useDynamicColor: Boolean = false,
    val oledEnhance: Boolean = false,
)

object ThemePreferenceStore {
  const val DEFAULT_THEME_MODE = "system"
  const val DEFAULT_SEED_COLOR_VALUE = 0xFF6750A4L

  private const val KEY_THEME_MODE = "appearance_theme_mode"
  private const val KEY_SEED_COLOR = "appearance_seed_color"
  private const val KEY_DYNAMIC_COLOR = "appearance_dynamic_color"
  private const val KEY_OLED_ENHANCE = "appearance_oled_enhance"

  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun save(preferences: StoredThemePreferences) {
    settings.putString(KEY_THEME_MODE, preferences.themeMode)
    settings.putString(KEY_SEED_COLOR, preferences.seedColorValue.toString())
    settings.putString(KEY_DYNAMIC_COLOR, preferences.useDynamicColor.toString())
    settings.putString(KEY_OLED_ENHANCE, preferences.oledEnhance.toString())
  }

  fun get(): StoredThemePreferences =
      StoredThemePreferences(
          themeMode = settings.getStringOrNull(KEY_THEME_MODE) ?: DEFAULT_THEME_MODE,
          seedColorValue =
              settings.getStringOrNull(KEY_SEED_COLOR)?.toLongOrNull() ?: DEFAULT_SEED_COLOR_VALUE,
          useDynamicColor =
              settings.getStringOrNull(KEY_DYNAMIC_COLOR)?.toBooleanStrictOrNull() ?: false,
          oledEnhance =
              settings.getStringOrNull(KEY_OLED_ENHANCE)?.toBooleanStrictOrNull() ?: false,
      )

  fun clear() {
    settings.remove(KEY_THEME_MODE)
    settings.remove(KEY_SEED_COLOR)
    settings.remove(KEY_DYNAMIC_COLOR)
    settings.remove(KEY_OLED_ENHANCE)
  }
}
