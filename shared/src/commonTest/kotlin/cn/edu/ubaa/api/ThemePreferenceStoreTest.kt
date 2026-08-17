package cn.edu.ubaa.api

import cn.edu.ubaa.api.storage.StoredThemePreferences
import cn.edu.ubaa.api.storage.ThemePreferenceStore
import com.russhwolf.settings.MapSettings
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals

class ThemePreferenceStoreTest {
  @BeforeTest
  fun resetStore() {
    ThemePreferenceStore.settings = MapSettings()
  }

  @Test
  fun `empty store returns default appearance preferences`() {
    assertEquals(
        StoredThemePreferences(
            themeMode = "system",
            seedColorValue = ThemePreferenceStore.DEFAULT_SEED_COLOR_VALUE,
            useDynamicColor = false,
            oledEnhance = false,
        ),
        ThemePreferenceStore.get(),
    )
  }

  @Test
  fun `appearance preferences round trip through settings`() {
    val preferences =
        StoredThemePreferences(
            themeMode = "dark",
            seedColorValue = 0xFFFF9800,
            useDynamicColor = true,
            oledEnhance = true,
        )

    ThemePreferenceStore.save(preferences)

    assertEquals(preferences, ThemePreferenceStore.get())
  }
}
