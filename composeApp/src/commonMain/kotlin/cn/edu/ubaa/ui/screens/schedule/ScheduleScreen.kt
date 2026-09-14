package cn.edu.ubaa.ui.screens.schedule

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.repository.ScheduleStore
import cn.edu.ubaa.ui.common.util.BackHandlerCompat
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.drop

val LocalScheduleResponseExporter = staticCompositionLocalOf<((String) -> Unit)?> { null }

/** 不授予在线登录状态，断网或会话过期时仍可读取上次登录账号的本地课表。 */
@Composable
fun OfflineScheduleScreen(
    onBack: () -> Unit,
    initialTermCode: String? = null,
    initialWeek: Int? = null,
) {
  BackHandlerCompat(onBack = onBack)
  val revision by ScheduleStore.changes.collectAsState()
  val account = remember(revision) { ScheduleStore.account() }
  val model: ScheduleViewModel =
      viewModel(key = "offline-schedule-$account") { ScheduleViewModel() }
  val state by model.uiState.collectAsState()
  val today by model.todayScheduleState.collectAsState()
  var course by remember { mutableStateOf<CourseClass?>(null) }
  LaunchedEffect(account) {
    model.resetLoadedState()
    model.ensureScheduleLoaded()
    model.uiState.value.terms.firstOrNull { it.itemCode == initialTermCode }?.let(model::selectTerm)
    model.uiState.value.weeks.firstOrNull { it.serialNumber == initialWeek }?.let(model::selectWeek)
    model.loadTodaySchedule()
    while (true) {
      delay(60_000)
      model.loadTodaySchedule()
      model.uiState.value.selectedTerm?.let(model::loadWeeks)
    }
  }
  Column(modifier = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
    Text(
        "今日课程 · 离线查看（账号尾号 ${account?.takeLast(4).orEmpty()}）",
        style = MaterialTheme.typography.titleSmall,
        modifier = Modifier.padding(16.dp),
    )
    Text(
        today.error
            ?: today.todayClasses
                .joinToString("\n") { "${it.time.orEmpty()}  ${it.bizName}  ${it.place.orEmpty()}" }
                .ifEmpty { "今天没有课程" },
        modifier =
            Modifier.padding(horizontal = 16.dp)
                .heightIn(max = 144.dp)
                .verticalScroll(rememberScrollState()),
    )
    ScheduleScreen(
        terms = state.terms,
        weeks = state.weeks,
        weeklySchedule = state.weeklySchedule,
        weekSchedules = state.weekSchedules,
        selectedTerm = state.selectedTerm,
        selectedWeek = state.selectedWeek,
        isLoading = false,
        error = state.error,
        onTermSelected = model::selectTerm,
        onWeekSelected = model::selectWeek,
        onNavigateBack = onBack,
        onCourseClick = { course = it },
        updatedAt = state.updatedAt,
        modifier = Modifier.weight(1f),
    )
  }
  course?.let { item ->
    AlertDialog(
        onDismissRequest = { course = null },
        title = { Text(item.courseName) },
        text = {
          Text(
              listOfNotNull(
                      item.placeName,
                      "${item.beginTime.orEmpty()}-${item.endTime.orEmpty()}",
                      item.weeksAndTeachers,
                  )
                  .joinToString("\n")
          )
        },
        confirmButton = { TextButton(onClick = { course = null }) { Text("关闭") } },
    )
  }
}

/**
 * 课表展示主屏幕。 以网格形式展示选定周次的课程安排，并提供周次切换功能。
 *
 * @param terms 所有可选学期列表。
 * @param weeks 当前学期的所有周次列表。
 * @param weeklySchedule 当前选定周次的排课数据。
 * @param selectedTerm 当前选中的学期。
 * @param selectedWeek 当前选中的周次。
 * @param isLoading 是否正在加载数据。
 * @param error 错误信息。
 * @param onTermSelected 学期选择回调。
 * @param onWeekSelected 周次选择回调。
 * @param onNavigateBack 返回上一级页面的回调。
 * @param onCourseClick 点击课程单元格的回调。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(
    terms: List<Term>,
    weeks: List<Week>,
    weeklySchedule: WeeklySchedule?,
    selectedTerm: Term?,
    selectedWeek: Week?,
    isLoading: Boolean,
    error: String?,
    onTermSelected: (Term) -> Unit,
    onWeekSelected: (Week) -> Unit,
    onNavigateBack: () -> Unit,
    onCourseClick: (CourseClass) -> Unit,
    modifier: Modifier = Modifier,
    isUpdating: Boolean = false,
    updatedAt: String? = null,
    onUpdate: (() -> Unit)? = null,
    onImportCurrentTerm: (() -> Unit)? = null,
    diagnosticResponse: String? = null,
    weekSchedules: Map<Int, WeeklySchedule> = emptyMap(),
) {
  val clipboard = LocalClipboardManager.current
  val exportResponse = LocalScheduleResponseExporter.current
  var responseCopied by remember(diagnosticResponse) { mutableStateOf(false) }
  var showWeekSelector by remember { mutableStateOf(false) }
  var showTermSelector by remember { mutableStateOf(false) }
  val currentWeekIndex = weeks.indexOf(selectedWeek)

  Scaffold(
      topBar = {
        ScheduleTopAppBar(
            title = selectedWeek?.name ?: "选择周次",
            onNavigateBack = onNavigateBack,
            onPreviousClick = {
              if (currentWeekIndex > 0) onWeekSelected(weeks[currentWeekIndex - 1])
            },
            isPreviousEnabled = currentWeekIndex > 0,
            onNextClick = {
              if (currentWeekIndex != -1 && currentWeekIndex < weeks.size - 1)
                  onWeekSelected(weeks[currentWeekIndex + 1])
            },
            isNextEnabled = currentWeekIndex != -1 && currentWeekIndex < weeks.size - 1,
            onTitleClick = { showWeekSelector = true },
        )
      },
      modifier = modifier,
  ) { paddingValues ->
    Column(modifier = Modifier.fillMaxSize().padding(paddingValues)) {
      Row(
          modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        Box(modifier = Modifier.weight(1f)) {
          TextButton(
              onClick = { showTermSelector = true },
              enabled = (terms.isNotEmpty() || onImportCurrentTerm != null) && !isUpdating,
          ) {
            Text(selectedTerm?.itemName ?: "尚未导入学期", maxLines = 2)
          }
          DropdownMenu(
              expanded = showTermSelector,
              onDismissRequest = { showTermSelector = false },
          ) {
            if (onImportCurrentTerm != null)
                DropdownMenuItem(
                    text = { Text("导入系统当前学期") },
                    onClick = {
                      showTermSelector = false
                      onImportCurrentTerm()
                    },
                )
            terms.forEach { term ->
              DropdownMenuItem(
                  text = { Text(term.itemName) },
                  onClick = {
                    showTermSelector = false
                    onTermSelected(term)
                  },
              )
            }
          }
        }
        if (onUpdate != null)
            TextButton(onClick = onUpdate, enabled = !isUpdating) {
              Text(if (isUpdating) "正在导入…" else "更新课表")
            }
      }
      Text(
          text = updatedAt?.let { "本地课表 · 更新于 $it" } ?: "首次使用请联网更新课表，之后可离线查看",
          style = MaterialTheme.typography.labelSmall,
          modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
      )
      if (isUpdating) LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
      if (error != null)
          Text(
              text = error,
              color = MaterialTheme.colorScheme.error,
              style = MaterialTheme.typography.bodySmall,
              modifier = Modifier.padding(12.dp),
          )
      if (error != null && diagnosticResponse != null) {
        if (exportResponse != null) {
          Button(
              onClick = { exportResponse(diagnosticResponse) },
              modifier = Modifier.padding(horizontal = 12.dp),
          ) {
            Text("导出响应文件（TXT）")
          }
        }
        TextButton(
            onClick = {
              clipboard.setText(AnnotatedString(diagnosticResponse))
              responseCopied = true
            }
        ) {
          Text(if (responseCopied) "已复制响应，可粘贴给排查人员" else "复制本次课表响应")
        }
        Text(
            "响应可能包含姓名、学号及课程信息，请勿公开发布。不会复制请求 Cookie 或密码。",
            style = MaterialTheme.typography.labelSmall,
            modifier = Modifier.padding(horizontal = 12.dp),
        )
      }
      Box(modifier = Modifier.weight(1f)) {
        when {
          isLoading && weeklySchedule == null -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
              Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                Spacer(modifier = Modifier.height(8.dp))
                Text("加载课程表...")
              }
            }
          }
          weeklySchedule != null && selectedWeek != null -> {
            key(selectedTerm?.itemCode) {
              ScheduleWeekPager(
                  weeks,
                  selectedWeek,
                  weekSchedules.ifEmpty { mapOf(selectedWeek.serialNumber to weeklySchedule) },
                  onWeekSelected,
                  onCourseClick,
              )
            }
          }
          else -> {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
              Text(
                  text =
                      if (updatedAt != null && weeks.isEmpty()) "此学期暂无已安排课程" else "请先更新课表，再选择学期和周次",
                  style = MaterialTheme.typography.bodyLarge,
                  color = MaterialTheme.colorScheme.onSurfaceVariant,
              )
            }
          }
        }
      }
    }
  }

  if (showWeekSelector) {
    WeekSelectionSheet(
        weeks = weeks,
        selectedWeek = selectedWeek,
        onWeekSelected = {
          onWeekSelected(it)
          showWeekSelector = false
        },
        onDismiss = { showWeekSelector = false },
    )
  }
}

/** Pager 同时绘制相邻两周，拖动跟手，松手后吸附；只消费本地快照。 */
@Composable
internal fun ScheduleWeekPager(
    weeks: List<Week>,
    selectedWeek: Week,
    schedules: Map<Int, WeeklySchedule>,
    onWeekSelected: (Week) -> Unit,
    onCourseClick: (CourseClass) -> Unit,
) {
  val index = weeks.indexOfFirst { it.serialNumber == selectedWeek.serialNumber }.coerceAtLeast(0)
  val pager = rememberPagerState(initialPage = index, pageCount = { weeks.size })
  val callback by rememberUpdatedState(onWeekSelected)
  val currentWeeks by rememberUpdatedState(weeks)
  val selected by rememberUpdatedState(selectedWeek)
  val times = remember(schedules) { scheduleSectionTimes(schedules.values) }
  LaunchedEffect(index) { if (pager.currentPage != index) pager.animateScrollToPage(index) }
  LaunchedEffect(pager) {
    snapshotFlow { pager.isScrollInProgress to pager.settledPage }
        .drop(1)
        .collect { (moving, page) ->
          if (!moving)
              currentWeeks
                  .getOrNull(page)
                  ?.takeIf { it.serialNumber != selected.serialNumber }
                  ?.let(callback)
        }
  }
  HorizontalPager(
      state = pager,
      modifier = Modifier.fillMaxSize().testTag("week-pager"),
      beyondViewportPageCount = 1,
      key = { weeks[it].serialNumber },
  ) { page ->
    val week = weeks[page]
    val schedule = schedules[week.serialNumber]
    if (schedule != null)
        WeeklyScheduleView(schedule, week.headerDayLabels(), onCourseClick, times = times)
    else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text("此周尚未保存，请更新课表") }
  }
}

/** 课表页面专用顶部栏。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ScheduleTopAppBar(
    title: String,
    onNavigateBack: () -> Unit,
    onPreviousClick: () -> Unit,
    isPreviousEnabled: Boolean,
    onNextClick: () -> Unit,
    isNextEnabled: Boolean,
    onTitleClick: () -> Unit,
) {
  CenterAlignedTopAppBar(
      expandedHeight = 56.dp,
      navigationIcon = {
        IconButton(onClick = onNavigateBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "返回") }
      },
      title = {
        Row(
            modifier = Modifier.clickable(onClick = onTitleClick),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(
              text = title,
              fontWeight = FontWeight.Bold,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
          )
        }
      },
      actions = {
        IconButton(onClick = onPreviousClick, enabled = isPreviousEnabled) {
          Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "上一周")
        }
        IconButton(onClick = onNextClick, enabled = isNextEnabled) {
          Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "下一周")
        }
      },
  )
}

/** 周次选择底部弹窗。 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WeekSelectionSheet(
    weeks: List<Week>,
    selectedWeek: Week?,
    onWeekSelected: (Week) -> Unit,
    onDismiss: () -> Unit,
) {
  ModalBottomSheet(onDismissRequest = onDismiss) {
    LazyColumn(contentPadding = PaddingValues(bottom = 32.dp)) {
      item {
        Text(
            text = "选择周次",
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(16.dp),
        )
      }
      items(weeks) { week ->
        ListItem(
            headlineContent = { Text(week.name) },
            modifier = Modifier.clickable { onWeekSelected(week) },
            leadingContent = {
              if (week.curWeek)
                  Surface(
                      color = MaterialTheme.colorScheme.secondaryContainer,
                      shape = RoundedCornerShape(4.dp),
                  ) {
                    Text(
                        text = "本周",
                        style = MaterialTheme.typography.labelSmall,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                    )
                  }
            },
            trailingContent = {
              if (week == selectedWeek)
                  Icon(Icons.Default.Check, "已选择", tint = MaterialTheme.colorScheme.primary)
            },
        )
      }
    }
  }
}

/** 核心周课表视图组件。包含星期标题行、时间轴列和课程网格。 */
@Composable
private fun WeeklyScheduleView(
    schedule: WeeklySchedule,
    headerDayLabels: List<ScheduleHeaderDayLabel>,
    onCourseClick: (CourseClass) -> Unit,
    modifier: Modifier = Modifier,
    times: List<SectionTime> = scheduleSectionTimes(listOf(schedule)),
) {
  val totalPeriods = times.size
  val rowHeight: Dp = 64.dp
  val scrollState = rememberScrollState()

  Column(modifier = modifier.padding(horizontal = 8.dp)) {
    HeaderRow(headerDayLabels)
    Spacer(modifier = Modifier.height(4.dp))
    Row(
        modifier =
            Modifier.fillMaxWidth()
                .verticalScroll(scrollState)
                .background(
                    MaterialTheme.colorScheme.surfaceVariant.copy(0.3f),
                    RoundedCornerShape(8.dp),
                )
    ) {
      TimeColumn(times, rowHeight, Modifier.width(52.dp))
      WeeklyScheduleGrid(schedule, onCourseClick, totalPeriods, rowHeight, Modifier.weight(1f))
    }
  }
}

/** 星期标题行。 */
@Composable
private fun HeaderRow(dayLabels: List<ScheduleHeaderDayLabel>) {
  Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
    Spacer(modifier = Modifier.width(52.dp))
    dayLabels.forEach {
      Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
          Text(text = it.weekdayLabel, fontSize = 12.sp, fontWeight = FontWeight.Medium)
          it.dateLabel?.let { dateLabel ->
            Text(
                text = dateLabel,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
          }
        }
      }
    }
  }
}

/** 时间轴列。 */
@Composable
private fun TimeColumn(
    timeLabels: List<SectionTime>,
    rowHeight: Dp,
    modifier: Modifier = Modifier,
) {
  Column(modifier = modifier) {
    timeLabels.forEach {
      Box(
          modifier = Modifier.height(rowHeight).fillMaxWidth(),
          contentAlignment = Alignment.Center,
      ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
          Text(text = it.section.toString(), fontSize = 12.sp, fontWeight = FontWeight.Medium)
          Text(
              text = it.start ?: "--:--",
              fontSize = 10.sp,
              lineHeight = 13.sp,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
          Text(
              text = it.end ?: "--:--",
              fontSize = 10.sp,
              lineHeight = 13.sp,
              color = MaterialTheme.colorScheme.onSurfaceVariant,
          )
        }
      }
    }
  }
}

/** 课程表网格。负责绘制背景辅助线和摆放课程单元格。 */
@Composable
private fun WeeklyScheduleGrid(
    schedule: WeeklySchedule,
    onCourseClick: (CourseClass) -> Unit,
    totalPeriods: Int,
    rowHeight: Dp,
    modifier: Modifier = Modifier,
) {
  val totalDays = 7
  val gridColor = MaterialTheme.colorScheme.onSurface.copy(0.1f)
  BoxWithConstraints(modifier = modifier.height(rowHeight * totalPeriods)) {
    val density = LocalDensity.current
    val cellHeightPx = with(density) { rowHeight.toPx() }
    val cellWidth = maxWidth / totalDays

    Canvas(modifier = Modifier.fillMaxSize()) {
      val pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 10f), 0f)
      for (i in 1 until totalPeriods) {
        val y = i * cellHeightPx
        drawLine(gridColor, Offset(0f, y), Offset(size.width, y), pathEffect = pathEffect)
      }
      for (i in 1 until totalDays) {
        val x = i * cellWidth.toPx()
        drawLine(gridColor, Offset(x, 0f), Offset(x, size.height))
      }
    }

    schedule.arrangedList.forEach { course ->
      val dayIndex = (course.dayOfWeek ?: 1) - 1
      val startIdx = (course.beginSection ?: 1) - 1
      val span = (course.endSection ?: course.beginSection ?: 1) - (course.beginSection ?: 1) + 1
      if (dayIndex in 0 until totalDays && startIdx in 0 until totalPeriods) {
        CourseCell(
            course,
            { onCourseClick(course) },
            Modifier.offset(cellWidth * dayIndex, rowHeight * startIdx)
                .size(cellWidth, rowHeight * span)
                .padding(1.dp),
        )
      }
    }
  }
}

/** 单个课程卡片组件。 */
@Composable
private fun CourseCell(course: CourseClass, onClick: () -> Unit, modifier: Modifier = Modifier) {
  val isDark = isSystemInDarkTheme()
  val parsedColor = remember(course.color) { parseColor(course.color) }
  val containerColor =
      remember(parsedColor, isDark) {
        val base = parsedColor ?: Color(0xFF6200EE)
        if (isDark && parsedColor != null) base.copy(alpha = 0.7f) else base
      }
  val contentColor = if (containerColor.luminance() > 0.5f) Color.Black else Color.White

  Card(
      modifier = modifier.fillMaxSize().clickable { onClick() },
      shape = RoundedCornerShape(6.dp),
      colors =
          CardDefaults.cardColors(containerColor = containerColor, contentColor = contentColor),
  ) {
    Column(
        modifier = Modifier.fillMaxSize().padding(4.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
      Text(
          text = course.courseName,
          fontSize = 12.sp,
          fontWeight = FontWeight.Bold,
          textAlign = TextAlign.Center,
          lineHeight = 14.sp,
          maxLines = 4,
          overflow = TextOverflow.Ellipsis,
      )
      course.placeName?.let {
        Text(
            text = "@$it",
            fontSize = 11.sp,
            textAlign = TextAlign.Center,
            lineHeight = 13.sp,
            color = contentColor.copy(0.8f),
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
      }
    }
  }
}

/** 解析十六进制颜色字符串。 */
private fun parseColor(colorString: String?): Color? {
  return try {
    if (colorString?.startsWith("#") == true && colorString.length == 7) {
      Color(colorString.substring(1).toInt(16) or (0xFF shl 24))
    } else null
  } catch (_: Exception) {
    null
  }
}
