package cn.edu.ubaa.api

import cn.edu.ubaa.api.storage.YgdkReminderStore
import com.russhwolf.settings.MapSettings
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class YgdkReminderStoreTest {

  @AfterTest
  fun tearDown() {
    YgdkReminderStore.settings = MapSettings()
  }

  @Test
  fun `reminder is enabled by default and isolated by user key`() {
    YgdkReminderStore.settings = MapSettings()

    assertTrue(YgdkReminderStore.isEnabled("23373270"))

    YgdkReminderStore.setEnabled("23373270", false)

    assertFalse(YgdkReminderStore.isEnabled("23373270"))
    assertTrue(YgdkReminderStore.isEnabled("other"))
  }

  @Test
  fun `week and term done keys are isolated by user and period`() {
    YgdkReminderStore.settings = MapSettings()

    YgdkReminderStore.markWeekDone("23373270", "2025-2026-2:11")
    YgdkReminderStore.markTermDone("23373270", "2025-2026-2")

    assertTrue(YgdkReminderStore.isWeekDone("23373270", "2025-2026-2:11"))
    assertFalse(YgdkReminderStore.isWeekDone("23373270", "2025-2026-2:12"))
    assertFalse(YgdkReminderStore.isWeekDone("other", "2025-2026-2:11"))
    assertTrue(YgdkReminderStore.isTermDone("23373270", "2025-2026-2"))
    assertFalse(YgdkReminderStore.isTermDone("23373270", "2026-2027-1"))
    assertFalse(YgdkReminderStore.isTermDone("other", "2025-2026-2"))
  }

  @Test
  fun `clear removes only target user reminder state`() {
    YgdkReminderStore.settings = MapSettings()
    YgdkReminderStore.setEnabled("23373270", false)
    YgdkReminderStore.markWeekDone("23373270", "2025-2026-2:11")
    YgdkReminderStore.markTermDone("23373270", "2025-2026-2")
    YgdkReminderStore.setEnabled("other", false)
    YgdkReminderStore.markWeekDone("other", "2025-2026-2:11")
    YgdkReminderStore.markTermDone("other", "2025-2026-2")

    YgdkReminderStore.clear("23373270")

    assertTrue(YgdkReminderStore.isEnabled("23373270"))
    assertFalse(YgdkReminderStore.isWeekDone("23373270", "2025-2026-2:11"))
    assertFalse(YgdkReminderStore.isTermDone("23373270", "2025-2026-2"))
    assertFalse(YgdkReminderStore.isEnabled("other"))
    assertTrue(YgdkReminderStore.isWeekDone("other", "2025-2026-2:11"))
    assertTrue(YgdkReminderStore.isTermDone("other", "2025-2026-2"))
  }
}
