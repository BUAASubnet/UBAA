package cn.edu.ubaa.ui.screens.bykc

import cn.edu.ubaa.api.StoredBykcCourseFilters
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import cn.edu.ubaa.model.dto.BykcCourseSubCategory

private val bykcStatusOrder =
    listOf(
        BykcCourseStatus.PREVIEW,
        BykcCourseStatus.AVAILABLE,
        BykcCourseStatus.FULL,
        BykcCourseStatus.SELECTED,
        BykcCourseStatus.ENDED,
        BykcCourseStatus.EXPIRED,
    )

private val bykcCategoryOrder =
    BykcCourseSubCategory.entries
        .filter { it != BykcCourseSubCategory.UNKNOWN }
        .map { it.displayName }

data class BykcCourseFilters(
    val statuses: Set<BykcCourseStatus> = emptySet(),
    val categories: Set<String> = emptySet(),
    val campuses: Set<String> = emptySet(),
) {
  val hasActiveSelections: Boolean
    get() = statuses.isNotEmpty() || categories.isNotEmpty() || campuses.isNotEmpty()

  fun requiresAllCourses(): Boolean =
      statuses.isEmpty() ||
          BykcCourseStatus.EXPIRED in statuses ||
          BykcCourseStatus.ENDED in statuses
}

fun defaultBykcCourseFilters(): BykcCourseFilters =
    BykcCourseFilters(
        statuses =
            setOf(
                BykcCourseStatus.SELECTED,
                BykcCourseStatus.PREVIEW,
                BykcCourseStatus.FULL,
                BykcCourseStatus.AVAILABLE,
            )
    )

data class BykcCourseFilterOptions(
    val statuses: List<BykcCourseStatus>,
    val categories: List<String>,
    val campuses: List<String>,
)

fun buildBykcCourseFilterOptions(
    courses: List<BykcCourseDto>,
    selectedCampuses: Set<String> = emptySet(),
): BykcCourseFilterOptions {
  val categories = bykcCategoryOrder
  val campuses =
      (courses.flatMap { it.audienceCampuses } + selectedCampuses)
          .map { it.trim() }
          .filter { it.isNotEmpty() }
          .distinct()
          .sortedWith(bykcCampusComparator)

  return BykcCourseFilterOptions(
      statuses = bykcStatusOrder,
      categories = categories,
      campuses = campuses,
  )
}

fun filterBykcCourses(
    courses: List<BykcCourseDto>,
    filters: BykcCourseFilters,
): List<BykcCourseDto> {
  return courses.filter { it.matches(filters) }
}

fun BykcCourseFilters.hasCustomSelections(
    defaultFilters: BykcCourseFilters = defaultBykcCourseFilters()
): Boolean = this != defaultFilters

fun BykcCourseFilters.activeLabels(
    defaultFilters: BykcCourseFilters = defaultBykcCourseFilters()
): List<String> {
  return buildList {
    if (statuses != defaultFilters.statuses) {
      if (statuses.isEmpty()) {
        add("状态: 不限")
      } else {
        addAll(bykcStatusOrder.filter { it in statuses }.map { "状态: ${it.displayName}" })
      }
    }
    addAll(categories.toList().sortedWith(bykcCategoryComparator).map { "类别: $it" })
    addAll(campuses.toList().sortedWith(bykcCampusComparator).map { "校区: $it" })
  }
}

fun BykcCourseFilters.toggleStatus(status: BykcCourseStatus): BykcCourseFilters =
    copy(statuses = statuses.toggle(status))

fun BykcCourseFilters.toggleCategory(category: String): BykcCourseFilters =
    copy(categories = categories.toggle(category))

fun BykcCourseFilters.toggleCampus(campus: String): BykcCourseFilters =
    copy(campuses = campuses.toggle(campus))

fun BykcCourseFilters.toStored(): StoredBykcCourseFilters =
    StoredBykcCourseFilters(
        statuses = bykcStatusOrder.filter { it in statuses }.map { it.name },
        categories = categories.toList().sortedWith(bykcCategoryComparator),
        campuses = campuses.toList().sortedWith(bykcCampusComparator),
    )

fun StoredBykcCourseFilters.toBykcCourseFilters(): BykcCourseFilters =
    BykcCourseFilters(
        statuses = statuses.mapNotNull(::parseStoredBykcCourseStatus).toSet(),
        categories = categories.map { it.trim() }.filter { it.isNotEmpty() }.toSet(),
        campuses = campuses.map { it.trim() }.filter { it.isNotEmpty() }.toSet(),
    )

private fun BykcCourseDto.matches(filters: BykcCourseFilters): Boolean {
  if (filters.statuses.isNotEmpty() && filters.statuses.none { matchesStatus(it) }) return false
  if (filters.categories.isNotEmpty() && filterCategoryLabel() !in filters.categories) return false
  if (filters.campuses.isNotEmpty() && audienceCampuses.none { it in filters.campuses })
      return false
  return true
}

private fun BykcCourseDto.matchesStatus(status: BykcCourseStatus): Boolean {
  return when (status) {
    BykcCourseStatus.FULL -> !selected && isDisplayedAsFull()
    BykcCourseStatus.AVAILABLE -> this.status == BykcCourseStatus.AVAILABLE && !isDisplayedAsFull()
    else -> this.status == status
  }
}

private fun BykcCourseDto.filterCategoryLabel(): String? {
  return subCategory?.displayName ?: category?.displayName
}

private fun BykcCourseDto.isDisplayedAsFull(): Boolean {
  val currentCount = courseCurrentCount
  val isEnrollmentFull =
      currentCount != null && courseMaxCount > 0 && currentCount >= courseMaxCount
  return status == BykcCourseStatus.FULL ||
      (status == BykcCourseStatus.AVAILABLE && isEnrollmentFull)
}

private fun <T> Set<T>.toggle(value: T): Set<T> = if (value in this) this - value else this + value

private fun parseStoredBykcCourseStatus(name: String): BykcCourseStatus? =
    BykcCourseStatus.entries.firstOrNull { it.name == name }

private val bykcCampusComparator =
    compareBy<String>(
        { bykcCampusRank(it) },
        { it },
    )

private fun bykcCampusRank(label: String): Int {
  return when {
    label.startsWith("学院路") -> 0
    label.startsWith("沙河") -> 1
    label.startsWith("杭州") -> 2
    label == "未指定校区" -> 3
    else -> 4
  }
}

private val bykcCategoryComparator =
    compareBy<String>(
        { bykcCategoryOrder.indexOf(it).takeIf { index -> index >= 0 } ?: Int.MAX_VALUE },
        { it },
    )
