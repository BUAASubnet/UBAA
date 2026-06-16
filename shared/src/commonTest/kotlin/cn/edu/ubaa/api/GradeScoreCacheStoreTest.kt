package cn.edu.ubaa.api

import cn.edu.ubaa.api.storage.GradeScoreCacheStore
import cn.edu.ubaa.api.storage.StoredGradeScoreCache
import cn.edu.ubaa.api.storage.StoredGradeScoreEntry
import com.russhwolf.settings.MapSettings
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GradeScoreCacheStoreTest {
  @AfterTest
  fun tearDown() {
    ConnectionModeStore.settings = MapSettings()
    GradeScoreCacheStore.settings = MapSettings()
  }

  @Test
  fun `cache is isolated by user and connection mode`() {
    ConnectionModeStore.settings = MapSettings()
    GradeScoreCacheStore.settings = MapSettings()

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)
    GradeScoreCacheStore.save("test-user", sampleCache("2025-2026-1", "95"))
    GradeScoreCacheStore.save("other", sampleCache("2025-2026-1", "80"))

    assertEquals("95", GradeScoreCacheStore.get("test-user")?.scores?.singleOrNull()?.score)
    assertEquals("80", GradeScoreCacheStore.get("other")?.scores?.singleOrNull()?.score)

    ConnectionModeStore.save(ConnectionMode.DIRECT)

    assertNull(GradeScoreCacheStore.get("test-user"))

    GradeScoreCacheStore.save("test-user", sampleCache("2025-2026-1", "100"))

    assertEquals("100", GradeScoreCacheStore.get("test-user")?.scores?.singleOrNull()?.score)

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)

    assertEquals("95", GradeScoreCacheStore.get("test-user")?.scores?.singleOrNull()?.score)
  }

  @Test
  fun `clear all scopes removes indexed cache entries`() {
    ConnectionModeStore.settings = MapSettings()
    GradeScoreCacheStore.settings = MapSettings()

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)
    GradeScoreCacheStore.save("test-user", sampleCache("2025-2026-1", "95"))
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    GradeScoreCacheStore.save("test-user", sampleCache("2025-2026-1", "100"))

    GradeScoreCacheStore.clearAllScopes()

    assertNull(GradeScoreCacheStore.get("test-user"))

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)

    assertNull(GradeScoreCacheStore.get("test-user"))
  }

  private fun sampleCache(termCode: String, score: String): StoredGradeScoreCache =
      StoredGradeScoreCache(
          termCode = termCode,
          termName = termCode,
          scores =
              listOf(
                  StoredGradeScoreEntry(
                      key = "course:math",
                      courseName = "高等数学",
                      courseCode = "MATH",
                      score = score,
                  )
              ),
      )
}
