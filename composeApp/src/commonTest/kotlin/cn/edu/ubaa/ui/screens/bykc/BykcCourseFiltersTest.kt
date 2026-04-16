package cn.edu.ubaa.ui.screens.bykc

import cn.edu.ubaa.model.dto.BykcCourseCategory
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import cn.edu.ubaa.model.dto.BykcCourseSubCategory
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BykcCourseFiltersTest {

  @Test
  fun `defaultBykcCourseFilters selects all non-historical statuses`() {
    assertEquals(
        setOf(
            BykcCourseStatus.SELECTED,
            BykcCourseStatus.PREVIEW,
            BykcCourseStatus.FULL,
            BykcCourseStatus.AVAILABLE,
        ),
        defaultBykcCourseFilters().statuses,
    )
  }

  @Test
  fun `filterBykcCourses supports multi-dimensional multi-select intersection`() {
    val courses =
        listOf(
            course(
                id = 1,
                status = BykcCourseStatus.AVAILABLE,
                subCategory = BykcCourseSubCategory.MORAL,
                campuses = listOf("学院路校区"),
            ),
            course(
                id = 2,
                status = BykcCourseStatus.FULL,
                subCategory = BykcCourseSubCategory.MORAL,
                campuses = listOf("沙河校区"),
            ),
            course(
                id = 3,
                status = BykcCourseStatus.PREVIEW,
                subCategory = BykcCourseSubCategory.AESTHETIC,
                campuses = listOf("沙河校区"),
            ),
        )

    val filters =
        BykcCourseFilters(
            statuses = setOf(BykcCourseStatus.AVAILABLE, BykcCourseStatus.PREVIEW),
            categories = setOf("德育", "美育"),
            campuses = setOf("学院路校区"),
        )

    assertEquals(listOf(1L), filterBykcCourses(courses, filters).map { it.id })
  }

  @Test
  fun `buildBykcCourseFilterOptions always shows five fixed categories and deduplicated campuses`() {
    val courses =
        listOf(
            course(
                id = 1,
                subCategory = BykcCourseSubCategory.MORAL,
                campuses = listOf("未指定校区", "学院路校区"),
            ),
            course(
                id = 2,
                subCategory = BykcCourseSubCategory.AESTHETIC,
                campuses = listOf("学院路校区", "沙河校区", "杭州校区"),
            ),
        )

    val options = buildBykcCourseFilterOptions(courses)

    assertEquals(
        listOf(
            BykcCourseStatus.PREVIEW,
            BykcCourseStatus.AVAILABLE,
            BykcCourseStatus.FULL,
            BykcCourseStatus.SELECTED,
            BykcCourseStatus.ENDED,
            BykcCourseStatus.EXPIRED,
        ),
        options.statuses,
    )
    assertEquals(listOf("德育", "美育", "劳动教育", "安全健康", "其他方面"), options.categories)
    assertEquals(listOf("学院路校区", "沙河校区", "杭州校区", "未指定校区"), options.campuses)
  }

  @Test
  fun `buildBykcCourseFilterOptions keeps selected campuses even after data reload`() {
    val courses = listOf(course(id = 1, campuses = listOf("学院路校区")))

    val options = buildBykcCourseFilterOptions(courses, selectedCampuses = setOf("未指定校区", "杭州校区"))

    assertEquals(listOf("学院路校区", "杭州校区", "未指定校区"), options.campuses)
  }

  @Test
  fun `requiresAllCourses only turns on for ended or expired filters`() {
    assertTrue(BykcCourseFilters().requiresAllCourses())
    assertFalse(
        BykcCourseFilters(statuses = setOf(BykcCourseStatus.AVAILABLE)).requiresAllCourses()
    )
    assertTrue(BykcCourseFilters(statuses = setOf(BykcCourseStatus.ENDED)).requiresAllCourses())
    assertTrue(BykcCourseFilters(statuses = setOf(BykcCourseStatus.EXPIRED)).requiresAllCourses())
  }

  @Test
  fun `activeLabels hides default statuses until user changes them`() {
    assertTrue(defaultBykcCourseFilters().activeLabels(defaultBykcCourseFilters()).isEmpty())
    assertEquals(
        listOf("状态: 选课结束"),
        BykcCourseFilters(statuses = setOf(BykcCourseStatus.ENDED))
            .activeLabels(defaultBykcCourseFilters()),
    )
    assertEquals(
        listOf("状态: 不限"),
        BykcCourseFilters(statuses = emptySet()).activeLabels(defaultBykcCourseFilters()),
    )
    assertEquals(
        listOf(
            "状态: 不限",
            "类别: 美育",
            "校区: 学院路校区",
            "校区: 杭州校区",
            "校区: 未指定校区",
        ),
        BykcCourseFilters(
                categories = setOf("美育"),
                campuses = setOf("未指定校区", "杭州校区", "学院路校区"),
            )
            .activeLabels(defaultBykcCourseFilters()),
    )
  }

  @Test
  fun `stored filters round trip preserves empty statuses for unrestricted view`() {
    val filters =
        BykcCourseFilters(
            statuses = emptySet(),
            categories = setOf("美育"),
            campuses = setOf("学院路校区"),
        )

    assertEquals(filters, filters.toStored().toBykcCourseFilters())
  }

  @Test
  fun `full status filter still matches effectively full course`() {
    val courses =
        listOf(
            course(
                id = 1,
                status = BykcCourseStatus.AVAILABLE,
                currentCount = 40,
                maxCount = 40,
            ),
            course(
                id = 2,
                status = BykcCourseStatus.AVAILABLE,
                currentCount = 39,
                maxCount = 40,
            ),
        )

    val filtered =
        filterBykcCourses(courses, BykcCourseFilters(statuses = setOf(BykcCourseStatus.FULL)))

    assertEquals(listOf(1L), filtered.map { it.id })
  }

  @Test
  fun `full status filter excludes courses displayed as selected or ended`() {
    val courses =
        listOf(
            course(
                id = 1,
                status = BykcCourseStatus.AVAILABLE,
                currentCount = 40,
                maxCount = 40,
            ),
            course(
                id = 2,
                status = BykcCourseStatus.ENDED,
                currentCount = 40,
                maxCount = 40,
            ),
            course(
                id = 3,
                status = BykcCourseStatus.FULL,
                currentCount = 40,
                maxCount = 40,
                selected = true,
            ),
        )

    val filtered =
        filterBykcCourses(courses, BykcCourseFilters(statuses = setOf(BykcCourseStatus.FULL)))

    assertEquals(listOf(1L), filtered.map { it.id })
  }

  @Test
  fun `available status filter excludes effectively full courses`() {
    val courses =
        listOf(
            course(
                id = 1,
                status = BykcCourseStatus.AVAILABLE,
                currentCount = 39,
                maxCount = 40,
            ),
            course(
                id = 2,
                status = BykcCourseStatus.AVAILABLE,
                currentCount = 40,
                maxCount = 40,
            ),
        )

    val filtered =
        filterBykcCourses(courses, BykcCourseFilters(statuses = setOf(BykcCourseStatus.AVAILABLE)))

    assertEquals(listOf(1L), filtered.map { it.id })
  }

  private fun course(
      id: Long,
      status: BykcCourseStatus = BykcCourseStatus.AVAILABLE,
      subCategory: BykcCourseSubCategory? = null,
      campuses: List<String> = emptyList(),
      currentCount: Int? = null,
      maxCount: Int = 50,
      selected: Boolean = false,
  ): BykcCourseDto =
      BykcCourseDto(
          id = id,
          courseName = "课程$id",
          category = BykcCourseCategory.BOYA,
          subCategory = subCategory,
          audienceCampuses = campuses,
          courseCurrentCount = currentCount,
          courseMaxCount = maxCount,
          status = status,
          selected = selected,
      )
}
