package cn.edu.ubaa.api

import com.russhwolf.settings.MapSettings
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class BykcCourseFilterStoreTest {

  @AfterTest
  fun tearDown() {
    BykcCourseFilterStore.settings = MapSettings()
  }

  @Test
  fun `save and get are isolated by user key`() {
    BykcCourseFilterStore.settings = MapSettings()

    BykcCourseFilterStore.save(
        "23373270",
        StoredBykcCourseFilters(
            statuses = listOf("AVAILABLE", "FULL"),
            categories = listOf("德育"),
            campuses = listOf("学院路校区"),
        ),
    )
    BykcCourseFilterStore.save(
        "other",
        StoredBykcCourseFilters(statuses = listOf("ENDED")),
    )

    assertEquals(
        StoredBykcCourseFilters(
            statuses = listOf("AVAILABLE", "FULL"),
            categories = listOf("德育"),
            campuses = listOf("学院路校区"),
        ),
        BykcCourseFilterStore.get("23373270"),
    )
    assertEquals(
        StoredBykcCourseFilters(statuses = listOf("ENDED")),
        BykcCourseFilterStore.get("other"),
    )
  }

  @Test
  fun `clear removes only target user filters`() {
    BykcCourseFilterStore.settings = MapSettings()

    BykcCourseFilterStore.save("23373270", StoredBykcCourseFilters(statuses = listOf("AVAILABLE")))
    BykcCourseFilterStore.save("other", StoredBykcCourseFilters(statuses = listOf("ENDED")))

    BykcCourseFilterStore.clear("23373270")

    assertNull(BykcCourseFilterStore.get("23373270"))
    assertEquals(
        StoredBykcCourseFilters(statuses = listOf("ENDED")),
        BykcCourseFilterStore.get("other"),
    )
  }
}
