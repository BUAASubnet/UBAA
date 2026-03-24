package cn.edu.ubaa.ui.navigation

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.model.dto.CourseClass
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import cn.edu.ubaa.ui.common.components.AppTopBar
import cn.edu.ubaa.ui.common.components.BottomNavTab
import cn.edu.ubaa.ui.common.components.BottomNavigation
import cn.edu.ubaa.ui.common.components.Sidebar
import cn.edu.ubaa.ui.common.util.BackHandlerCompat
import cn.edu.ubaa.ui.screens.bykc.*
import cn.edu.ubaa.ui.screens.cgyy.CgyyHomeScreen
import cn.edu.ubaa.ui.screens.cgyy.CgyyLockCodeScreen
import cn.edu.ubaa.ui.screens.cgyy.CgyyOrdersScreen
import cn.edu.ubaa.ui.screens.cgyy.CgyyReserveFormScreen
import cn.edu.ubaa.ui.screens.cgyy.CgyyReservePickerScreen
import cn.edu.ubaa.ui.screens.cgyy.CgyyViewModel
import cn.edu.ubaa.ui.screens.classroom.ClassroomQueryScreen
import cn.edu.ubaa.ui.screens.classroom.ClassroomViewModel
import cn.edu.ubaa.ui.screens.evaluation.EvaluationScreen
import cn.edu.ubaa.ui.screens.evaluation.EvaluationViewModel
import cn.edu.ubaa.ui.screens.exam.ExamScreen
import cn.edu.ubaa.ui.screens.exam.ExamViewModel
import cn.edu.ubaa.ui.screens.menu.*
import cn.edu.ubaa.ui.screens.schedule.CourseDetailScreen
import cn.edu.ubaa.ui.screens.schedule.ScheduleScreen
import cn.edu.ubaa.ui.screens.schedule.ScheduleViewModel
import cn.edu.ubaa.ui.screens.signin.SigninScreen
import cn.edu.ubaa.ui.screens.signin.SigninViewModel
import cn.edu.ubaa.ui.screens.spoc.SpocAssignmentDetailScreen
import cn.edu.ubaa.ui.screens.spoc.SpocAssignmentsScreen
import cn.edu.ubaa.ui.screens.spoc.SpocSortField
import cn.edu.ubaa.ui.screens.spoc.SpocViewModel

/** 应用程序所有的屏幕页面定义。 */
enum class AppScreen {
  HOME,
  REGULAR,
  ADVANCED,
  MY,
  ABOUT,
  SCHEDULE,
  EXAM,
  COURSE_DETAIL,
  BYKC_HOME,
  BYKC_COURSES,
  BYKC_DETAIL,
  BYKC_CHOSEN,
  BYKC_STATISTICS,
  SIGNIN,
  CGYY_HOME,
  CGYY_RESERVE_PICKER,
  CGYY_RESERVE_FORM,
  CGYY_ORDERS,
  CGYY_LOCK_CODE,
  CLASSROOM_QUERY,
  EVALUATION,
  SPOC_ASSIGNMENTS,
  SPOC_ASSIGNMENT_DETAIL,
}

/**
 * 主界面支架组件。 整合了侧边栏、顶部栏、底部导航栏以及各业务模块的屏幕切换。 负责协调 ViewModel 的初始化和导航状态的分发。
 *
 * @param userData 登录用户的基础数据。
 * @param userInfo 登录用户的详细信息。
 * @param onLogoutClick 注销回调。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainAppScreen(
    userData: UserData,
    userInfo: UserInfo?,
    onLogoutClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
  val navController = rememberNavigationController()
  val currentScreen = navController.currentScreen

  var selectedBottomTab by remember { mutableStateOf(BottomNavTab.HOME) }
  var showSidebar by remember { mutableStateOf(false) }

  // 初始化各模块 ViewModel
  val scheduleViewModel: ScheduleViewModel = viewModel { ScheduleViewModel() }
  val scheduleUiState by scheduleViewModel.uiState.collectAsState()
  val todayScheduleState by scheduleViewModel.todayScheduleState.collectAsState()

  val examViewModel: ExamViewModel = viewModel { ExamViewModel() }
  val examUiState by examViewModel.uiState.collectAsState()
  var showExamTermMenu by remember { mutableStateOf(false) }

  val signinViewModel: SigninViewModel =
      viewModel(key = "signin-${userData.schoolid}") { SigninViewModel() }
  val evaluationViewModel: EvaluationViewModel = viewModel { EvaluationViewModel() }
  val cgyyViewModel: CgyyViewModel =
      viewModel(key = "cgyy-${userData.schoolid}") { CgyyViewModel() }
  val classroomViewModel: ClassroomViewModel = viewModel { ClassroomViewModel() }
  val spocViewModel: SpocViewModel =
      viewModel(key = "spoc-${userData.schoolid}") { SpocViewModel() }
  val spocUiState by spocViewModel.uiState.collectAsState()
  val bykcViewModel: BykcViewModel =
      viewModel(key = "bykc-${userData.schoolid}") { BykcViewModel() }
  val bykcCoursesState by bykcViewModel.coursesState.collectAsState()
  val bykcDetailState by bykcViewModel.courseDetailState.collectAsState()
  val bykcChosenState by bykcViewModel.chosenCoursesState.collectAsState()

  var selectedCourse by remember { mutableStateOf<CourseClass?>(null) }
  var selectedBykcCourseId by remember { mutableStateOf<Long?>(null) }
  var showBykcIncludeExpired by remember { mutableStateOf(false) }
  var hideBykcFullCourses by remember { mutableStateOf(false) }
  var selectedSpocAssignmentId by remember { mutableStateOf<String?>(null) }
  var showSpocSortFilterDialog by remember { mutableStateOf(false) }

  /** 重置导航栈至指定根页面。 */
  fun setRoot(screen: AppScreen, tab: BottomNavTab) {
    navController.setRoot(screen)
    selectedBottomTab = tab
    showSidebar = false
  }

  /** 跳转至指定页面，并自动更新底部 Tab 激活状态。 */
  fun navigateTo(screen: AppScreen, bottomTab: BottomNavTab? = null) {
    navController.navigateTo(screen)
    val tab =
        bottomTab
            ?: when (screen) {
              AppScreen.HOME -> BottomNavTab.HOME
              AppScreen.REGULAR,
              AppScreen.SCHEDULE,
              AppScreen.EXAM,
              AppScreen.COURSE_DETAIL,
              AppScreen.CLASSROOM_QUERY,
              AppScreen.SPOC_ASSIGNMENTS,
              AppScreen.SPOC_ASSIGNMENT_DETAIL -> BottomNavTab.REGULAR
              AppScreen.ADVANCED,
              AppScreen.BYKC_HOME,
              AppScreen.BYKC_COURSES,
              AppScreen.BYKC_DETAIL,
              AppScreen.BYKC_CHOSEN,
              AppScreen.BYKC_STATISTICS,
              AppScreen.SIGNIN,
              AppScreen.CGYY_HOME,
              AppScreen.CGYY_RESERVE_PICKER,
              AppScreen.CGYY_RESERVE_FORM,
              AppScreen.CGYY_ORDERS,
              AppScreen.CGYY_LOCK_CODE,
              AppScreen.EVALUATION -> BottomNavTab.ADVANCED
              else -> null
            }
    tab?.let { selectedBottomTab = it }
    if (screen !in listOf(AppScreen.MY, AppScreen.ABOUT)) showSidebar = false
  }

  /** 统一的返回逻辑处理。 */
  fun navigateBack() {
    if (navController.navigateBack()) {
      val top = navController.currentScreen
      val tab =
          when (top) {
            AppScreen.HOME -> BottomNavTab.HOME
            AppScreen.REGULAR,
            AppScreen.SCHEDULE,
            AppScreen.EXAM,
            AppScreen.COURSE_DETAIL,
            AppScreen.CLASSROOM_QUERY,
            AppScreen.SPOC_ASSIGNMENTS,
            AppScreen.SPOC_ASSIGNMENT_DETAIL -> BottomNavTab.REGULAR
            AppScreen.ADVANCED,
            AppScreen.BYKC_HOME,
            AppScreen.BYKC_COURSES,
            AppScreen.BYKC_DETAIL,
            AppScreen.BYKC_CHOSEN,
            AppScreen.BYKC_STATISTICS,
            AppScreen.SIGNIN,
            AppScreen.CGYY_HOME,
            AppScreen.CGYY_RESERVE_PICKER,
            AppScreen.CGYY_RESERVE_FORM,
            AppScreen.CGYY_ORDERS,
            AppScreen.CGYY_LOCK_CODE,
            AppScreen.EVALUATION -> BottomNavTab.ADVANCED
            else -> null
          }
      tab?.let { selectedBottomTab = it }
      if (top in listOf(AppScreen.MY, AppScreen.ABOUT)) showSidebar = true
    } else {
      selectedBottomTab =
          when (navController.currentScreen) {
            AppScreen.REGULAR -> BottomNavTab.REGULAR
            AppScreen.ADVANCED -> BottomNavTab.ADVANCED
            else -> BottomNavTab.HOME
          }
      showSidebar = false
    }
  }

  val screenTitle =
      when (currentScreen) {
        AppScreen.HOME -> "首页"
        AppScreen.REGULAR -> "普通功能"
        AppScreen.ADVANCED -> "高级功能"
        AppScreen.MY -> "我的"
        AppScreen.ABOUT -> "关于"
        AppScreen.SCHEDULE -> "课程表"
        AppScreen.EXAM -> "考试查询"
        AppScreen.COURSE_DETAIL -> "课程详情"
        AppScreen.BYKC_HOME -> "博雅课程"
        AppScreen.BYKC_COURSES -> "选择课程"
        AppScreen.BYKC_DETAIL -> "课程详情"
        AppScreen.BYKC_CHOSEN -> "我的课程"
        AppScreen.BYKC_STATISTICS -> "课程统计"
        AppScreen.SIGNIN -> "课程签到"
        AppScreen.CGYY_HOME -> "研讨室预约"
        AppScreen.CGYY_RESERVE_PICKER -> "预约研讨室"
        AppScreen.CGYY_RESERVE_FORM -> "填写预约信息"
        AppScreen.CGYY_ORDERS -> "我的预约"
        AppScreen.CGYY_LOCK_CODE -> "查看密码"
        AppScreen.CLASSROOM_QUERY -> "空教室查询"
        AppScreen.EVALUATION -> "自动评教"
        AppScreen.SPOC_ASSIGNMENTS -> "SPOC作业"
        AppScreen.SPOC_ASSIGNMENT_DETAIL -> "作业详情"
      }

  Box(modifier = modifier.fillMaxSize()) {
    BackHandlerCompat(enabled = showSidebar || navController.navStack.size > 1) {
      if (showSidebar) showSidebar = false else if (navController.navStack.size > 1) navigateBack()
    }

    Column(modifier = Modifier.fillMaxSize()) {
      val isRootScreen =
          currentScreen in listOf(AppScreen.HOME, AppScreen.REGULAR, AppScreen.ADVANCED)
      AppTopBar(
          title = screenTitle,
          canNavigateBack = !isRootScreen,
          onNavigationIconClick = {
            if (isRootScreen) showSidebar = !showSidebar else navigateBack()
          },
          actions = {
            // 特殊页面的顶部栏动作按钮
            if (currentScreen == AppScreen.EXAM) {
              Box {
                TextButton(onClick = { showExamTermMenu = true }) {
                  Text(examUiState.selectedTerm?.itemName ?: "选择学期")
                  Icon(Icons.Default.ArrowDropDown, null)
                }
                DropdownMenu(
                    expanded = showExamTermMenu,
                    onDismissRequest = { showExamTermMenu = false },
                ) {
                  examUiState.terms.forEach {
                    DropdownMenuItem(
                        text = { Text(it.itemName) },
                        onClick = {
                          examViewModel.selectTerm(it)
                          showExamTermMenu = false
                        },
                    )
                  }
                }
              }
            } else if (currentScreen == AppScreen.BYKC_COURSES) {
              Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "显示已过期",
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(end = 8.dp),
                )
                Checkbox(
                    checked = showBykcIncludeExpired,
                    onCheckedChange = {
                      showBykcIncludeExpired = it
                      bykcViewModel.loadCourses(includeExpired = it)
                    },
                )
              }
            } else if (currentScreen == AppScreen.SPOC_ASSIGNMENTS) {
              IconButton(onClick = { showSpocSortFilterDialog = true }) {
                Icon(Icons.Default.Tune, contentDescription = "排序和筛选")
              }
            }
          },
      )

      Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
        when (currentScreen) {
          AppScreen.HOME ->
              HomeScreen(
                  todayClasses = todayScheduleState.todayClasses,
                  isLoading = todayScheduleState.isLoading,
                  error = todayScheduleState.error,
                  onRefresh = { scheduleViewModel.loadTodaySchedule() },
              )
          AppScreen.REGULAR ->
              RegularFeaturesScreen(
                  onScheduleClick = { navigateTo(AppScreen.SCHEDULE) },
                  onExamClick = { navigateTo(AppScreen.EXAM) },
                  onBykcClick = { navigateTo(AppScreen.BYKC_HOME) },
                  onClassroomClick = { navigateTo(AppScreen.CLASSROOM_QUERY) },
                  onSpocClick = { navigateTo(AppScreen.SPOC_ASSIGNMENTS) },
              )
          AppScreen.ADVANCED ->
              AdvancedFeaturesScreen(
                  onSigninClick = { navigateTo(AppScreen.SIGNIN) },
                  onCgyyClick = { navigateTo(AppScreen.CGYY_HOME) },
                  onEvaluationClick = { navigateTo(AppScreen.EVALUATION) },
              )
          AppScreen.MY -> MyScreen(userInfo = userInfo)
          AppScreen.ABOUT -> AboutScreen()
          AppScreen.SCHEDULE ->
              ScheduleScreen(
                  terms = scheduleUiState.terms,
                  weeks = scheduleUiState.weeks,
                  weeklySchedule = scheduleUiState.weeklySchedule,
                  selectedTerm = scheduleUiState.selectedTerm,
                  selectedWeek = scheduleUiState.selectedWeek,
                  isLoading = scheduleUiState.isLoading,
                  error = scheduleUiState.error,
                  onTermSelected = { scheduleViewModel.selectTerm(it) },
                  onWeekSelected = { scheduleViewModel.selectWeek(it) },
                  onCourseClick = {
                    selectedCourse = it
                    navigateTo(AppScreen.COURSE_DETAIL)
                  },
              )
          AppScreen.EXAM -> ExamScreen(viewModel = examViewModel)
          AppScreen.COURSE_DETAIL -> selectedCourse?.let { CourseDetailScreen(course = it) }
          AppScreen.BYKC_HOME ->
              BykcHomeScreen(
                  onSelectCourseClick = { navigateTo(AppScreen.BYKC_COURSES) },
                  onMyCoursesClick = { navigateTo(AppScreen.BYKC_CHOSEN) },
                  onStatisticsClick = {
                    bykcViewModel.loadStatistics()
                    navigateTo(AppScreen.BYKC_STATISTICS)
                  },
              )
          AppScreen.BYKC_STATISTICS -> BykcStatisticsScreen(viewModel = bykcViewModel)
          AppScreen.SIGNIN -> SigninScreen(viewModel = signinViewModel)
          AppScreen.BYKC_COURSES ->
              BykcCoursesScreen(
                  courses = bykcCoursesState.courses,
                  isLoading = bykcCoursesState.isLoading,
                  isLoadingMore = bykcCoursesState.isLoadingMore,
                  hasMorePages = bykcCoursesState.hasMorePages,
                  hideFullCourses = hideBykcFullCourses,
                  error = bykcCoursesState.error,
                  onCourseClick = {
                    selectedBykcCourseId = it.id
                    bykcViewModel.loadCourseDetail(it.id)
                    navigateTo(AppScreen.BYKC_DETAIL)
                  },
                  onHideFullCoursesChange = { hideBykcFullCourses = it },
                  onRefresh = {
                    bykcViewModel.loadCourses(includeExpired = showBykcIncludeExpired)
                  },
                  onLoadMore = {
                    bykcViewModel.loadMoreCourses(includeExpired = showBykcIncludeExpired)
                  },
              )
          AppScreen.BYKC_DETAIL ->
              BykcCourseDetailScreen(
                  course = bykcDetailState.course,
                  isLoading = bykcDetailState.isLoading,
                  error = bykcDetailState.error,
                  operationInProgress = bykcDetailState.operationInProgress,
                  operationMessage = bykcDetailState.operationMessage,
                  onSelectClick = {
                    selectedBykcCourseId?.let { bykcViewModel.selectCourse(it) { _, _ -> } }
                  },
                  onDeselectClick = {
                    selectedBykcCourseId?.let { bykcViewModel.deselectCourse(it) { _, _ -> } }
                  },
                  onSignInClick = {
                    selectedBykcCourseId?.let {
                      bykcViewModel.signCourse(it, null, null, 1) { _, _ -> }
                    }
                  },
                  onSignOutClick = {
                    selectedBykcCourseId?.let {
                      bykcViewModel.signCourse(it, null, null, 2) { _, _ -> }
                    }
                  },
                  onClearMessage = { bykcViewModel.clearOperationMessage() },
              )
          AppScreen.BYKC_CHOSEN ->
              BykcChosenCoursesScreen(
                  courses = bykcChosenState.courses,
                  isLoading = bykcChosenState.isLoading,
                  error = bykcChosenState.error,
                  onCourseClick = {
                    selectedBykcCourseId = it.courseId
                    bykcViewModel.loadCourseDetail(it.courseId)
                    navigateTo(AppScreen.BYKC_DETAIL)
                  },
                  onRefresh = { bykcViewModel.loadChosenCourses() },
              )
          AppScreen.CLASSROOM_QUERY ->
              ClassroomQueryScreen(viewModel = classroomViewModel, onBackClick = { navigateBack() })
          AppScreen.CGYY_HOME ->
              CgyyHomeScreen(
                  onReserveClick = { navigateTo(AppScreen.CGYY_RESERVE_PICKER) },
                  onOrdersClick = {
                    cgyyViewModel.ensureOrdersLoaded()
                    navigateTo(AppScreen.CGYY_ORDERS)
                  },
                  onLockCodeClick = { navigateTo(AppScreen.CGYY_LOCK_CODE) },
              )
          AppScreen.CGYY_RESERVE_PICKER ->
              CgyyReservePickerScreen(
                  viewModel = cgyyViewModel,
                  onNext = { navigateTo(AppScreen.CGYY_RESERVE_FORM) },
              )
          AppScreen.CGYY_RESERVE_FORM ->
              CgyyReserveFormScreen(
                  viewModel = cgyyViewModel,
                  onBackToSelection = { navigateBack() },
                  onSubmitSuccess = { navigateTo(AppScreen.CGYY_ORDERS) },
              )
          AppScreen.CGYY_ORDERS -> CgyyOrdersScreen(viewModel = cgyyViewModel)
          AppScreen.CGYY_LOCK_CODE -> CgyyLockCodeScreen(viewModel = cgyyViewModel)
          AppScreen.EVALUATION -> EvaluationScreen(viewModel = evaluationViewModel)
          AppScreen.SPOC_ASSIGNMENTS ->
              SpocAssignmentsScreen(
                  viewModel = spocViewModel,
                  onAssignmentClick = {
                    selectedSpocAssignmentId = it.assignmentId
                    spocViewModel.loadAssignmentDetail(it.assignmentId)
                    navigateTo(AppScreen.SPOC_ASSIGNMENT_DETAIL)
                  },
              )
          AppScreen.SPOC_ASSIGNMENT_DETAIL ->
              SpocAssignmentDetailScreen(
                  viewModel = spocViewModel,
                  onRetry = {
                    selectedSpocAssignmentId?.let { assignmentId ->
                      spocViewModel.loadAssignmentDetail(assignmentId)
                    }
                  },
              )
        }
      }

      if (
          currentScreen !in
              listOf(
                  AppScreen.SCHEDULE,
                  AppScreen.EXAM,
                  AppScreen.COURSE_DETAIL,
                  AppScreen.MY,
                  AppScreen.ABOUT,
                  AppScreen.BYKC_HOME,
                  AppScreen.BYKC_COURSES,
                  AppScreen.BYKC_DETAIL,
                  AppScreen.BYKC_CHOSEN,
                  AppScreen.BYKC_STATISTICS,
                  AppScreen.CLASSROOM_QUERY,
                  AppScreen.CGYY_HOME,
                  AppScreen.CGYY_RESERVE_PICKER,
                  AppScreen.CGYY_RESERVE_FORM,
                  AppScreen.CGYY_ORDERS,
                  AppScreen.CGYY_LOCK_CODE,
                  AppScreen.EVALUATION,
                  AppScreen.SPOC_ASSIGNMENTS,
                  AppScreen.SPOC_ASSIGNMENT_DETAIL,
              )
      ) {
        BottomNavigation(
            currentTab = selectedBottomTab,
            onTabSelected = { tab ->
              when (tab) {
                BottomNavTab.HOME -> setRoot(AppScreen.HOME, BottomNavTab.HOME)
                BottomNavTab.REGULAR -> setRoot(AppScreen.REGULAR, BottomNavTab.REGULAR)
                BottomNavTab.ADVANCED -> setRoot(AppScreen.ADVANCED, BottomNavTab.ADVANCED)
              }
            },
        )
      }
    }

    AnimatedVisibility(visible = showSidebar, enter = fadeIn(), exit = fadeOut()) {
      Box(
          Modifier.fillMaxSize().background(Color.Black.copy(0.5f)).clickable {
            showSidebar = false
          }
      )
    }

    AnimatedVisibility(
        visible = showSidebar,
        enter = slideInHorizontally(),
        exit = slideOutHorizontally(targetOffsetX = { -it * 2 }),
    ) {
      Box(Modifier.fillMaxHeight(), Alignment.CenterStart) {
        Sidebar(
            userData = userData,
            onLogoutClick = {
              showSidebar = false
              onLogoutClick()
            },
            onMyClick = {
              showSidebar = false
              navigateTo(AppScreen.MY)
            },
            onAboutClick = {
              showSidebar = false
              navigateTo(AppScreen.ABOUT)
            },
            modifier = Modifier.align(Alignment.CenterStart),
        )
      }
    }

    if (showSpocSortFilterDialog && currentScreen == AppScreen.SPOC_ASSIGNMENTS) {
      SpocSortFilterDialog(
          sortField = spocUiState.sortField,
          sortAscending = spocUiState.sortAscending,
          showExpired = spocUiState.showExpired,
          showOnlyUnsubmitted = spocUiState.showOnlyUnsubmitted,
          onDismiss = { showSpocSortFilterDialog = false },
          onApply = { sortField, sortAscending, showExpired, showOnlyUnsubmitted ->
            spocViewModel.setSortField(sortField)
            if (spocUiState.sortAscending != sortAscending) {
              spocViewModel.toggleSortDirection()
            }
            spocViewModel.setShowExpired(showExpired)
            spocViewModel.setShowOnlyUnsubmitted(showOnlyUnsubmitted)
            showSpocSortFilterDialog = false
          },
      )
    }
  }
}

@Composable
private fun SpocSortFilterDialog(
    sortField: SpocSortField,
    sortAscending: Boolean,
    showExpired: Boolean,
    showOnlyUnsubmitted: Boolean,
    onDismiss: () -> Unit,
    onApply: (SpocSortField, Boolean, Boolean, Boolean) -> Unit,
) {
  var selectedSortField by remember(sortField) { mutableStateOf(sortField) }
  var selectedSortAscending by remember(sortAscending) { mutableStateOf(sortAscending) }
  var selectedShowExpired by remember(showExpired) { mutableStateOf(showExpired) }
  var selectedShowOnlyUnsubmitted by
      remember(showOnlyUnsubmitted) { mutableStateOf(showOnlyUnsubmitted) }

  AlertDialog(
      onDismissRequest = onDismiss,
      title = { Text("排序和筛选") },
      text = {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
          Text("排序字段", style = MaterialTheme.typography.titleSmall)
          SpocDialogOptionRow(
              label = "按截止时间",
              selected = selectedSortField == SpocSortField.DUE_TIME,
              onClick = { selectedSortField = SpocSortField.DUE_TIME },
          )
          SpocDialogOptionRow(
              label = "按开始时间",
              selected = selectedSortField == SpocSortField.START_TIME,
              onClick = { selectedSortField = SpocSortField.START_TIME },
          )

          Text("排序方向", style = MaterialTheme.typography.titleSmall)
          SpocDialogOptionRow(
              label = "升序",
              selected = selectedSortAscending,
              onClick = { selectedSortAscending = true },
          )
          SpocDialogOptionRow(
              label = "降序",
              selected = !selectedSortAscending,
              onClick = { selectedSortAscending = false },
          )

          Text("筛选条件", style = MaterialTheme.typography.titleSmall)
          SpocCheckboxRow(
              label = "仅显示未提交",
              checked = selectedShowOnlyUnsubmitted,
              onCheckedChange = { selectedShowOnlyUnsubmitted = it },
          )
          SpocCheckboxRow(
              label = "显示已截止",
              checked = selectedShowExpired,
              onCheckedChange = { selectedShowExpired = it },
          )
        }
      },
      confirmButton = {
        TextButton(
            onClick = {
              onApply(
                  selectedSortField,
                  selectedSortAscending,
                  selectedShowExpired,
                  selectedShowOnlyUnsubmitted,
              )
            }
        ) {
          Text("应用")
        }
      },
      dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
  )
}

@Composable
private fun SpocDialogOptionRow(label: String, selected: Boolean, onClick: () -> Unit) {
  Row(
      modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
      verticalAlignment = Alignment.CenterVertically,
  ) {
    RadioButton(selected = selected, onClick = onClick)
    Text(text = label, style = MaterialTheme.typography.bodyMedium)
  }
}

@Composable
private fun SpocCheckboxRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
  Row(
      modifier = Modifier.fillMaxWidth().clickable(onClick = { onCheckedChange(!checked) }),
      verticalAlignment = Alignment.CenterVertically,
  ) {
    Checkbox(checked = checked, onCheckedChange = onCheckedChange)
    Text(text = label, style = MaterialTheme.typography.bodyMedium)
  }
}
