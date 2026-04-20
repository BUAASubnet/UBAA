package cn.edu.ubaa.ui.screens.bykc

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Label
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.delay
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterialApi::class, ExperimentalTime::class)
@Composable
fun BykcCoursesScreen(
    courses: List<BykcCourseDto>,
    isLoading: Boolean,
    isLoadingMore: Boolean,
    hasMorePages: Boolean,
    filters: BykcCourseFilters,
    error: String?,
    listState: LazyListState,
    onCourseClick: (BykcCourseDto) -> Unit,
    onFiltersChange: (BykcCourseFilters) -> Unit,
    onRefresh: () -> Unit,
    onLoadMore: () -> Unit,
    modifier: Modifier = Modifier,
) {
  val pullRefreshState = rememberPullRefreshState(refreshing = isLoading, onRefresh = onRefresh)
  var showFiltersDialog by remember { mutableStateOf(false) }
  val defaultFilters = remember { defaultBykcCourseFilters() }
  val now by
      produceState(
          initialValue = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
      ) {
        while (true) {
          delay(60_000)
          value = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        }
      }
  val filterOptions =
      remember(courses, filters.campuses) {
        buildBykcCourseFilterOptions(courses, selectedCampuses = filters.campuses)
      }
  val hasCustomSelections = remember(filters) { filters.hasCustomSelections(defaultFilters) }
  val activeFilterLabels = remember(filters) { filters.activeLabels(defaultFilters) }
  val visibleCourses = remember(courses, filters) { filterBykcCourses(courses, filters) }

  Box(modifier = modifier.fillMaxSize().pullRefresh(pullRefreshState)) {
    Column(modifier = Modifier.fillMaxSize()) {
      BykcCourseFiltersBar(
          filters = filters,
          activeFilterLabels = activeFilterLabels,
          hasCustomSelections = hasCustomSelections,
          onOpenFilters = { showFiltersDialog = true },
          onClearFilters = { onFiltersChange(defaultFilters) },
      )

      when {
        isLoading && courses.isEmpty() -> {
          Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) { Text("加载中...") }
          }
        }
        error != null -> {
          Box(
              modifier = Modifier.fillMaxSize().padding(16.dp),
              contentAlignment = Alignment.Center,
          ) {
            Text(text = "加载失败: $error", color = MaterialTheme.colorScheme.error)
          }
        }
        else -> {
          LazyColumn(
              state = listState,
              modifier = Modifier.fillMaxSize(),
              contentPadding = PaddingValues(16.dp),
              verticalArrangement = Arrangement.spacedBy(12.dp),
          ) {
            if (visibleCourses.isEmpty()) {
              item {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
                    contentAlignment = Alignment.Center,
                ) {
                  Text(
                      text =
                          if (hasCustomSelections && courses.isNotEmpty()) {
                            "当前筛选条件下暂无课程"
                          } else {
                            "暂无可选课程"
                          },
                      color = MaterialTheme.colorScheme.onSurfaceVariant,
                  )
                }
              }
            } else {
              items(visibleCourses, key = { it.id }) { course ->
                BykcCourseCard(course = course, now = now, onClick = { onCourseClick(course) })
              }
            }

            // 加载更多指示器
            if (hasMorePages) {
              item {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                  if (isLoadingMore) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                      CircularProgressIndicator(modifier = Modifier.size(24.dp))
                      Spacer(modifier = Modifier.height(8.dp))
                      Text("加载更多课程...", style = MaterialTheme.typography.bodySmall)
                    }
                  } else {
                    // 触发加载更多的区域
                    LaunchedEffect(Unit) { onLoadMore() }
                    Spacer(modifier = Modifier.height(16.dp))
                  }
                }
              }
            } else if (visibleCourses.isNotEmpty()) {
              item {
                Box(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                  Text(
                      "没有更多课程了",
                      style = MaterialTheme.typography.bodySmall,
                      color = MaterialTheme.colorScheme.onSurfaceVariant,
                  )
                }
              }
            }
          }
        }
      }
    }

    PullRefreshIndicator(
        refreshing = isLoading,
        state = pullRefreshState,
        modifier = Modifier.align(Alignment.TopCenter),
        backgroundColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.primary,
        scale = true,
    )
  }

  if (showFiltersDialog) {
    BykcCourseFiltersDialog(
        filters = filters,
        filterOptions = filterOptions,
        defaultFilters = defaultFilters,
        onDismissRequest = { showFiltersDialog = false },
        onFiltersChange = onFiltersChange,
    )
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BykcCourseFiltersBar(
    filters: BykcCourseFilters,
    activeFilterLabels: List<String>,
    hasCustomSelections: Boolean,
    onOpenFilters: () -> Unit,
    onClearFilters: () -> Unit,
) {
  BoxWithConstraints(
      modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)
  ) {
    val isCompact = maxWidth < 560.dp
    val verticalPadding = if (isCompact) 12.dp else 16.dp
    val titleText =
        when {
          hasCustomSelections && isCompact -> "筛选中 ${activeFilterLabels.size} 项"
          hasCustomSelections -> "已应用交叉筛选"
          else -> "课程筛选"
        }
    val subtitleText =
        when {
          isCompact && filters.requiresAllCourses() -> "包含选课结束和已过期课程"
          isCompact -> "默认仅显示仍可交互课程"
          filters.requiresAllCourses() -> "支持查看预告、可选、已选，以及选课结束/已过期课程"
          else -> "默认显示仍可交互课程，可按状态、类别、校区多选交叉筛选"
        }

    Surface(
        shape = RoundedCornerShape(if (isCompact) 18.dp else 22.dp),
        tonalElevation = if (isCompact) 2.dp else 3.dp,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
      Column(
          modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = verticalPadding)
      ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Row(
              modifier = Modifier.weight(1f),
              verticalAlignment = Alignment.CenterVertically,
              horizontalArrangement = Arrangement.spacedBy(if (isCompact) 10.dp else 12.dp),
          ) {
            Surface(
                shape = RoundedCornerShape(if (isCompact) 12.dp else 14.dp),
                color = MaterialTheme.colorScheme.primaryContainer,
            ) {
              Icon(
                  imageVector = Icons.Default.Tune,
                  contentDescription = null,
                  tint = MaterialTheme.colorScheme.onPrimaryContainer,
                  modifier = Modifier.padding(if (isCompact) 8.dp else 10.dp),
              )
            }
            Column(modifier = Modifier.weight(1f)) {
              Text(
                  text = titleText,
                  style = MaterialTheme.typography.titleSmall,
                  fontWeight = FontWeight.SemiBold,
                  maxLines = 1,
                  overflow = TextOverflow.Ellipsis,
              )
              Text(
                  text = subtitleText,
                  style = MaterialTheme.typography.bodySmall,
                  color = MaterialTheme.colorScheme.onSurfaceVariant,
                  maxLines = if (isCompact) 1 else 2,
                  overflow = TextOverflow.Ellipsis,
              )
            }
          }
          Spacer(modifier = Modifier.width(10.dp))
          if (isCompact) {
            FilledTonalIconButton(onClick = onOpenFilters) {
              Icon(Icons.Default.FilterList, contentDescription = "调整筛选")
            }
          } else {
            FilledTonalButton(onClick = onOpenFilters) {
              Icon(Icons.Default.FilterList, contentDescription = null)
              Spacer(modifier = Modifier.width(8.dp))
              Text(if (hasCustomSelections) "调整" else "筛选")
            }
          }
        }

        if (hasCustomSelections) {
          Spacer(modifier = Modifier.height(if (isCompact) 8.dp else 12.dp))
          if (isCompact) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
              Row(
                  modifier = Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                  horizontalArrangement = Arrangement.spacedBy(6.dp),
              ) {
                activeFilterLabels.forEach { label ->
                  SuggestionChip(
                      onClick = {},
                      label = {
                        Text(
                            text = label,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.labelMedium,
                        )
                      },
                      colors =
                          SuggestionChipDefaults.suggestionChipColors(
                              containerColor = MaterialTheme.colorScheme.secondaryContainer,
                              labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
                          ),
                  )
                }
              }
              Spacer(modifier = Modifier.width(6.dp))
              TextButton(
                  onClick = onClearFilters,
                  contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
              ) {
                Text("重置")
              }
            }
          } else {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
              Text(
                  text = "当前条件",
                  style = MaterialTheme.typography.labelLarge,
                  color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
              TextButton(onClick = onClearFilters) {
                Icon(Icons.Default.Clear, contentDescription = null)
                Spacer(modifier = Modifier.width(4.dp))
                Text("重置默认")
              }
            }
            Row(modifier = Modifier.horizontalScroll(rememberScrollState())) {
              FlowRow(
                  horizontalArrangement = Arrangement.spacedBy(6.dp),
                  verticalArrangement = Arrangement.spacedBy(6.dp),
              ) {
                activeFilterLabels.forEach { label ->
                  SuggestionChip(
                      onClick = {},
                      label = { Text(label) },
                      colors =
                          SuggestionChipDefaults.suggestionChipColors(
                              containerColor = MaterialTheme.colorScheme.secondaryContainer,
                              labelColor = MaterialTheme.colorScheme.onSecondaryContainer,
                          ),
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BykcCourseFiltersDialog(
    filters: BykcCourseFilters,
    filterOptions: BykcCourseFilterOptions,
    defaultFilters: BykcCourseFilters,
    onDismissRequest: () -> Unit,
    onFiltersChange: (BykcCourseFilters) -> Unit,
) {
  AlertDialog(
      onDismissRequest = onDismissRequest,
      confirmButton = { TextButton(onClick = onDismissRequest) { Text("完成") } },
      dismissButton = {
        if (filters.hasCustomSelections(defaultFilters)) {
          TextButton(onClick = { onFiltersChange(defaultFilters) }) { Text("重置默认") }
        }
      },
      title = {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Surface(
              shape = RoundedCornerShape(14.dp),
              color = MaterialTheme.colorScheme.primaryContainer,
          ) {
            Icon(
                imageVector = Icons.Default.Tune,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.padding(10.dp),
            )
          }
          Column {
            Text("筛选课程")
            Text(
                text = "多选后按状态、类别、校区交叉过滤",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }
      },
      text = {
        Column(modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState())) {
          BykcFilterSectionCard(
              title = "状态",
              selectedCount =
                  if (filters.statuses == defaultFilters.statuses) 0 else filters.statuses.size,
              icon = Icons.Default.FilterList,
              iconTint = MaterialTheme.colorScheme.primary,
              supportingText = "全部取消则表示状态不限",
          ) {
            filterOptions.statuses.forEach { status ->
              BykcFilterChip(
                  selected = status in filters.statuses,
                  onClick = { onFiltersChange(filters.toggleStatus(status)) },
                  label = status.displayName,
                  accentColor = MaterialTheme.colorScheme.primary,
              )
            }
          }

          if (filterOptions.categories.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))
            BykcFilterSectionCard(
                title = "类别",
                selectedCount = filters.categories.size,
                icon = Icons.AutoMirrored.Filled.Label,
                iconTint = MaterialTheme.colorScheme.tertiary,
                supportingText = "可任选多项",
            ) {
              filterOptions.categories.forEach { category ->
                BykcFilterChip(
                    selected = category in filters.categories,
                    onClick = { onFiltersChange(filters.toggleCategory(category)) },
                    label = category,
                    accentColor = MaterialTheme.colorScheme.tertiary,
                )
              }
            }
          }

          if (filterOptions.campuses.isNotEmpty()) {
            Spacer(modifier = Modifier.height(12.dp))
            BykcFilterSectionCard(
                title = "校区",
                selectedCount = filters.campuses.size,
                icon = Icons.Default.Place,
                iconTint = MaterialTheme.colorScheme.secondary,
                supportingText = "未指定即教师未设置开课地点所在校区",
            ) {
              filterOptions.campuses.forEach { campus ->
                BykcFilterChip(
                    selected = campus in filters.campuses,
                    onClick = { onFiltersChange(filters.toggleCampus(campus)) },
                    label = campus,
                    accentColor = MaterialTheme.colorScheme.secondary,
                )
              }
            }
          }
        }
      },
  )
}

@Composable
private fun BykcFilterChip(
    selected: Boolean,
    onClick: () -> Unit,
    label: String,
    accentColor: Color,
) {
  FilterChip(
      selected = selected,
      onClick = onClick,
      label = { Text(label) },
      leadingIcon =
          if (selected) {
            {
              Icon(
                  imageVector = Icons.Default.Check,
                  contentDescription = null,
                  tint = accentColor,
              )
            }
          } else null,
      colors =
          FilterChipDefaults.filterChipColors(
              selectedContainerColor = accentColor.copy(alpha = 0.14f),
              selectedLabelColor = accentColor,
              selectedLeadingIconColor = accentColor,
          ),
  )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BykcFilterSectionCard(
    title: String,
    selectedCount: Int,
    icon: ImageVector,
    iconTint: Color,
    supportingText: String,
    content: @Composable FlowRowScope.() -> Unit,
) {
  Surface(
      modifier = Modifier.fillMaxWidth(),
      shape = RoundedCornerShape(20.dp),
      tonalElevation = 2.dp,
      color = MaterialTheme.colorScheme.surfaceContainerLow,
      border = BorderStroke(1.dp, MaterialTheme.colorScheme.outlineVariant),
  ) {
    Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Surface(shape = RoundedCornerShape(12.dp), color = iconTint.copy(alpha = 0.12f)) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconTint,
                modifier = Modifier.padding(8.dp),
            )
          }
          Column {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = supportingText,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
          }
        }
        if (selectedCount > 0) {
          Surface(
              shape = RoundedCornerShape(999.dp),
              color = MaterialTheme.colorScheme.secondaryContainer,
          ) {
            Text(
                text = "已选 $selectedCount",
                modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSecondaryContainer,
            )
          }
        }
      }
      Spacer(modifier = Modifier.height(14.dp))
      FlowRow(
          horizontalArrangement = Arrangement.spacedBy(8.dp),
          verticalArrangement = Arrangement.spacedBy(8.dp),
          content = content,
      )
    }
  }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun BykcCourseCard(
    course: BykcCourseDto,
    now: kotlinx.datetime.LocalDateTime,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
  Card(
      modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
      shape = RoundedCornerShape(12.dp),
      elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
  ) {
    Column(modifier = Modifier.padding(16.dp)) {
      // 课程名称与状态
      Row(
          modifier = Modifier.fillMaxWidth(),
          horizontalArrangement = Arrangement.SpaceBetween,
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Text(
            text = course.courseName,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.weight(1f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        Spacer(modifier = Modifier.width(8.dp))

        CourseStatusChip(status = course.status, selected = course.selected)
      }

      Spacer(modifier = Modifier.height(8.dp))

      // 课程信息
      course.courseTeacher?.let { teacher -> InfoRow(label = "教师", value = teacher) }

      course.coursePosition?.let { position -> InfoRow(label = "地点", value = position) }

      course.courseStartDate?.let { startDate ->
        InfoRow(label = "时间", value = formatDateRangeOrStart(startDate, course.courseEndDate))
      }
      val selectTimeDisplay =
          resolveSelectTimeDisplay(
              startDate = course.courseSelectStartDate,
              endDate = course.courseSelectEndDate,
              now = now,
          )
      selectTimeDisplay?.let { selectTime ->
        InfoRow(label = selectTime.label, value = selectTime.value)
      }

      // 分类与签到标签
      if (course.subCategory != null || course.hasSignPoints) {
        Spacer(modifier = Modifier.height(4.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
          course.subCategory?.let { subCategory ->
            SuggestionChip(
                onClick = {},
                label = {
                  Text(subCategory.displayName, style = MaterialTheme.typography.labelSmall)
                },
            )
          }
          if (course.hasSignPoints) {
            SuggestionChip(
                onClick = {},
                label = { Text("自主签到", style = MaterialTheme.typography.labelSmall) },
            )
          }
        }
      }

      // 选课情况
      Spacer(modifier = Modifier.height(8.dp))
      val currentCount = course.courseCurrentCount
      val progress =
          remember(currentCount, course.courseMaxCount) {
            if (currentCount != null && course.courseMaxCount > 0) {
              (currentCount.toFloat() / course.courseMaxCount.toFloat()).coerceIn(
                  0f,
                  1f,
              )
            } else 0f
          }
      LinearProgressIndicator(
          progress = { progress },
          modifier = Modifier.fillMaxWidth().height(6.dp),
      )
      Spacer(modifier = Modifier.height(4.dp))
      Text(
          text =
              currentCount?.let { "已报名 $it / ${course.courseMaxCount}" }
                  ?: "人数上限 ${course.courseMaxCount}",
          style = MaterialTheme.typography.bodySmall,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
  }
}

@Composable
fun CourseStatusChip(status: BykcCourseStatus, selected: Boolean) {
  val (containerColor, labelColor) =
      when {
        selected ->
            Pair(
                MaterialTheme.colorScheme.primaryContainer,
                MaterialTheme.colorScheme.onPrimaryContainer,
            )
        status == BykcCourseStatus.AVAILABLE ->
            Pair(
                MaterialTheme.colorScheme.tertiaryContainer,
                MaterialTheme.colorScheme.onTertiaryContainer,
            )
        status == BykcCourseStatus.FULL ||
            status == BykcCourseStatus.ENDED ||
            status == BykcCourseStatus.EXPIRED ->
            Pair(
                MaterialTheme.colorScheme.errorContainer,
                MaterialTheme.colorScheme.onErrorContainer,
            )
        else ->
            Pair(
                MaterialTheme.colorScheme.secondaryContainer,
                MaterialTheme.colorScheme.onSecondaryContainer,
            )
      }

  AssistChip(
      onClick = {},
      label = {
        Text(
            text = if (selected) BykcCourseStatus.SELECTED.displayName else status.displayName,
            style = MaterialTheme.typography.labelMedium,
            color = labelColor,
        )
      },
      leadingIcon =
          if (selected) {
            { Icon(Icons.Default.Check, contentDescription = null, tint = labelColor) }
          } else null,
      colors =
          AssistChipDefaults.assistChipColors(
              containerColor = containerColor,
              labelColor = labelColor,
          ),
  )
}

@Composable
fun InfoRow(label: String, value: String) {
  Row(modifier = Modifier.padding(vertical = 2.dp)) {
    Text(
        text = "$label: ",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
    Text(
        text = value,
        style = MaterialTheme.typography.bodyMedium,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
  }
}
