package cn.edu.ubaa

import cn.edu.ubaa.api.auth.AppAnnouncement
import cn.edu.ubaa.api.auth.AppUpdateStatus
import cn.edu.ubaa.api.auth.AppVersionCheckResponse
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppStartupDialogStateTest {
  @Test
  fun announcementDialogWaitsUntilUpdateDialogIsClosed() {
    val announcement =
        AppAnnouncement(
            id = "2026-05-07-main",
            title = "公告",
            content = "公告正文",
        )
    val update =
        AppVersionCheckResponse(
            latestVersion = "1.5.0",
            status = AppUpdateStatus.UPDATE_AVAILABLE,
            updateAvailable = true,
            downloadUrl = "https://download.example.com",
        )

    assertFalse(shouldShowAnnouncementDialog(update, announcement))
    assertTrue(shouldShowAnnouncementDialog(null, announcement))
  }

  @Test
  fun confirmingAnnouncementMarksReadAndOpensConfiguredLink() {
    val openedLinks = mutableListOf<String>()
    val readIds = mutableListOf<String>()

    confirmAnnouncement(
        announcement =
            AppAnnouncement(
                id = "2026-05-07-main",
                title = "公告",
                content = "公告正文",
                linkUrl = "https://example.com/notice",
            ),
        openUri = { openedLinks.add(it) },
        markRead = { readIds.add(it) },
    )

    assertEquals(listOf("2026-05-07-main"), readIds)
    assertEquals(listOf("https://example.com/notice"), openedLinks)
  }

  @Test
  fun confirmingAnnouncementWithoutLinkOnlyMarksRead() {
    val openedLinks = mutableListOf<String>()
    val readIds = mutableListOf<String>()

    confirmAnnouncement(
        announcement =
            AppAnnouncement(
                id = "2026-05-07-main",
                title = "公告",
                content = "公告正文",
            ),
        openUri = { openedLinks.add(it) },
        markRead = { readIds.add(it) },
    )

    assertEquals(listOf("2026-05-07-main"), readIds)
    assertTrue(openedLinks.isEmpty())
  }
}
