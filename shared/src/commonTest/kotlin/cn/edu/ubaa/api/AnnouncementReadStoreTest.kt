package cn.edu.ubaa.api

import cn.edu.ubaa.api.storage.AnnouncementReadStore
import com.russhwolf.settings.MapSettings
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AnnouncementReadStoreTest {
  @BeforeTest
  fun resetStore() {
    AnnouncementReadStore.settings = MapSettings()
  }

  @Test
  fun announcementStartsUnreadAndCanBeMarkedRead() {
    assertFalse(AnnouncementReadStore.isRead("2026-05-07-main"))

    AnnouncementReadStore.markRead("2026-05-07-main")

    assertTrue(AnnouncementReadStore.isRead("2026-05-07-main"))
  }

  @Test
  fun differentAnnouncementIdsAreTrackedSeparately() {
    AnnouncementReadStore.markRead("2026-05-07-main")

    assertTrue(AnnouncementReadStore.isRead("2026-05-07-main"))
    assertFalse(AnnouncementReadStore.isRead("2026-05-08-main"))
  }
}
