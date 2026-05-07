package cn.edu.ubaa.announcement

import cn.edu.ubaa.api.auth.AppAnnouncement
import java.nio.file.Files
import kotlin.io.path.deleteIfExists
import kotlin.io.path.writeText
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AnnouncementServiceTest {
  @Test
  fun readsEnabledAnnouncementFromRuntimeFile() {
    val file = Files.createTempFile("ubaa-announcement", ".json")
    try {
      file.writeText(
          """
          {
            "enabled": true,
            "id": "2026-05-07-main",
            "title": "公告",
            "content": "公告正文",
            "confirmText": "我知道了",
            "linkUrl": "https://example.com/notice"
          }
          """
              .trimIndent()
      )

      val announcement = AnnouncementService(file.toFile()).currentAnnouncement()

      assertEquals(
          AppAnnouncement(
              id = "2026-05-07-main",
              title = "公告",
              content = "公告正文",
              confirmText = "我知道了",
              linkUrl = "https://example.com/notice",
          ),
          announcement,
      )
    } finally {
      file.deleteIfExists()
    }
  }

  @Test
  fun returnsNullWhenFileIsMissing() {
    val file = Files.createTempDirectory("ubaa-announcement").resolve("announcement.json")

    assertNull(AnnouncementService(file.toFile()).currentAnnouncement())
  }

  @Test
  fun returnsNullWhenAnnouncementIsDisabled() {
    val file = Files.createTempFile("ubaa-announcement", ".json")
    try {
      file.writeText(
          """
          {
            "enabled": false,
            "id": "2026-05-07-main",
            "title": "公告",
            "content": "公告正文"
          }
          """
              .trimIndent()
      )

      assertNull(AnnouncementService(file.toFile()).currentAnnouncement())
    } finally {
      file.deleteIfExists()
    }
  }

  @Test
  fun returnsNullWhenRequiredFieldsAreBlank() {
    val file = Files.createTempFile("ubaa-announcement", ".json")
    try {
      file.writeText(
          """
          {
            "enabled": true,
            "id": "   ",
            "title": "公告",
            "content": "公告正文"
          }
          """
              .trimIndent()
      )

      assertNull(AnnouncementService(file.toFile()).currentAnnouncement())
    } finally {
      file.deleteIfExists()
    }
  }

  @Test
  fun returnsNullWhenJsonIsInvalid() {
    val file = Files.createTempFile("ubaa-announcement", ".json")
    try {
      file.writeText("{ invalid json")

      assertNull(AnnouncementService(file.toFile()).currentAnnouncement())
    } finally {
      file.deleteIfExists()
    }
  }
}
