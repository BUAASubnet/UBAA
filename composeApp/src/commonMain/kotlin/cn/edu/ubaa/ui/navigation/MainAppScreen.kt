package cn.edu.ubaa.ui.navigation

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.rememberLazyListState
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
import cn.edu.ubaa.api.BykcCourseFilterStore
import cn.edu.ubaa.model.dto.BykcCourseDto
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
import cn.edu.ubaa.ui.screens.cgyy.CgyyUiState
import cn.edu.ubaa.ui.screens.cgyy.CgyyViewModel
import cn.edu.ubaa.ui.screens.classroom.ClassroomQueryScreen
import cn.edu.ubaa.ui.screens.classroom.ClassroomViewModel
import cn.edu.ubaa.ui.screens.evaluation.EvaluationScreen
import cn.edu.ubaa.ui.screens.evaluation.EvaluationViewModel
import cn.edu.ubaa.ui.screens.exam.ExamScreen
import cn.edu.ubaa.ui.screens.exam.ExamUiState
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
import cn.edu.ubaa.ui.screens.ygdk.YgdkClockinFormScreen
import cn.edu.ubaa.ui.screens.ygdk.YgdkHomeScreen
import cn.edu.ubaa.ui.screens.ygdk.YgdkUiState
import cn.edu.ubaa.ui.screens.ygdk.YgdkViewModel
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.delay
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

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
  YGDK_HOME,
  YGDK_FORM,
}

/**
 * 主界面支架组件。 整合了侧边栏、顶部栏、底部导航栏以及各业务模块的屏幕切换。 负责协调 ViewModel 的初始化和导航状态的分发。
 *
 * @param userData 登录用户的基础数据。
 * @param userInfo 登录用户的详细信息。
 * @param onLogoutClick 注销回调。
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalTime::class)
@Composable
fun MainAppScreen(
    userData: UserData,
    userInfo: UserInfo?,
    onEnsureUserInfo: () -> Unit,
    onLogoutClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
  val scope = rememberCoroutineScope()
  val navController = rememberNavigationController()
  val currentScreen = navController.currentScreen
  val cgyyScreens = remember {
    setOf(
        AppScreen.CGYY_HOME,
        AppScreen.CGYY_RESERVE_PICKER,
        AppScreen.CGYY_RESERVE_FORM,
        AppScreen.CGYY_ORDERS,
        AppScreen.CGYY_LOCK_CODE,
    )
  }
  val ygdkScreens = remember { setOf(AppScreen.YGDK_HOME, AppScreen.YGDK_FORM) }

  var selectedBottomTab by remember { mutableStateOf(BottomNavTab.HOME) }
  var showSidebar by remember { mutableStateOf(false) }
  val homeSnackbarHostState = remember { SnackbarHostState() }
  val homeBootstrapCoordinator = remember(scope) { HomeBootstrapCoordinator(scope) }
  val homeBootstrapRunning by homeBootstrapCoordinator.isRunning.collectAsState()
  val homeNow by
      produceState(
          initialValue = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
      ) {
        while (true) {
          delay(60_000)
          value = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        }
      }
  var hasVisitedCgyy by remember { mutableStateOf(false) }
  val shouldKeepCgyyViewModel =
      currentScreen == AppScreen.HOME || hasVisitedCgyy || currentScreen in cgyyScreens

  // 初始化各模块 ViewModel
  val scheduleViewModel: ScheduleViewModel = viewModel { ScheduleViewModel() }
  val scheduleUiState by scheduleViewModel.uiState.collectAsState()
  val todayScheduleState by scheduleViewModel.todayScheduleState.collectAsState()

  val examViewModel: ExamViewModel? =
      if (currentScreen == AppScreen.EXAM) {
        viewModel(key = "exam") { ExamViewModel() }
      } else {
        null
      }
  val examUiState = examViewModel?.uiState?.collectAsState()?.value ?: ExamUiState()
  var showExamTermMenu by remember { mutableStateOf(false) }

  val signinViewModel: SigninViewModel =
      viewModel(key = "signin-${userData.schoolid}") { SigninViewModel() }
  val signinUiState by signinViewModel.uiState.collectAsState()
  val evaluationViewModel: EvaluationViewModel? =
      if (currentScreen == AppScreen.EVALUATION) {
        viewModel(key = "evaluation") { EvaluationViewModel() }
      } else {
        null
      }
  val cgyyViewModel: CgyyViewModel? =
      if (shouldKeepCgyyViewModel) {
        viewModel(key = "cgyy-${userData.schoolid}") { CgyyViewModel() }
      } else {
        null
      }
  val cgyyUiState = cgyyViewModel?.uiState?.collectAsState()?.value ?: CgyyUiState()
  val classroomViewModel: ClassroomViewModel? =
      if (currentScreen == AppScreen.CLASSROOM_QUERY) {
        viewModel(key = "classroom") { ClassroomViewModel() }
      } else {
        null
      }
  val spocViewModel: SpocViewModel =
      viewModel(key = "spoc-${userData.schoolid}") { SpocViewModel() }
  val spocUiState by spocViewModel.uiState.collectAsState()
  val bykcViewModel: BykcViewModel =
      viewModel(key = "bykc-${userData.schoolid}") { BykcViewModel() }
  val bykcCoursesState by bykcViewModel.coursesState.collectAsState()
  val bykcDetailState by bykcViewModel.courseDetailState.collectAsState()
  val bykcChosenState by bykcViewModel.chosenCoursesState.collectAsState()
  val ygdkViewModel: YgdkViewModel? =
      if (currentScreen in ygdkScreens) {
        viewModel(key = "ygdk-${userData.schoolid}") { YgdkViewModel() }
      } else {
        null
      }
  val ygdkUiState = ygdkViewModel?.uiState?.collectAsState()?.value ?: YgdkUiState()

  var selectedCourse by remember { mutableStateOf<CourseClass?>(null) }
  var selectedBykcCourseId by remember { mutableStateOf<Long?>(null) }
  var selectedBykcCourseSnapshot by remember { mutableStateOf<BykcCourseDto?>(null) }
  val bykcCoursesListState = rememberLazyListState()
  val bykcFilterUserKey = userData.schoolid
  val defaultBykcFilters = remember { defaultBykcCourseFilters() }
  var bykcCourseFilters by
      remember(bykcFilterUserKey) {
        mutableStateOf(
            BykcCourseFilterStore.get(bykcFilterUserKey)?.toBykcCourseFilters()
                ?: defaultBykcFilters
        )
      }
  var selectedSpocAssignmentId by remember { mutableStateOf<String?>(null) }
  var showSpocSortFilterDialog by remember { mutableStateOf(false) }
  val homeTodoItems =
      remember(
          bykcChosenState.courses,
          spocUiState.assignmentsResponse,
          cgyyUiState.orders.content,
          signinUiState.classes,
          homeNow,
      ) {
        buildHomeTodoItems(
            bykcCourses = bykcChosenState.courses,
            spocAssignments = spocUiState.assignmentsResponse?.assignments.orEmpty(),
            cgyyOrders = cgyyUiState.orders.content,
            signinClasses = signinUiState.classes,
            now = homeNow,
        )
      }
  val homeTodoLoading =
      homeBootstrapRunning ||
          bykcChosenState.isLoading ||
          spocUiState.isLoading ||
          spocUiState.isRefreshing ||
          signinUiState.isLoading ||
          cgyyUiState.isOrdersLoading
  val homeTodoFailedSources = buildList {
    if (bykcChosenState.error != null) add(HomeTodoSource.BYKC)
    if (spocUiState.error != null) add(HomeTodoSource.SPOC)
    if (cgyyUiState.ordersError != null) add(HomeTodoSource.CGYY)
    if (signinUiState.error != null) add(HomeTodoSource.SIGNIN)
  }

  fun startHomeBootstrap(forceRefresh: Boolean = false) {
    val showLoading =
        forceRefresh ||
            !scheduleViewModel.hasTodayLoaded() ||
            !signinViewModel.hasTodayLoaded() ||
            !spocViewModel.hasAssignmentsLoaded() ||
            !bykcViewModel.hasChosenCoursesLoaded() ||
            cgyyViewModel?.hasOrdersLoaded() != true
    homeBootstrapCoordinator.restart(
        HomeBootstrapActions(
            loadTodaySchedule = { force ->
              scheduleViewModel.ensureTodayLoaded(forceRefresh = force)
            },
            loadSignin = { force -> signinViewModel.ensureTodayLoaded(forceRefresh = force) },
            loadSpoc = { force -> spocViewModel.ensureAssignmentsLoaded(forceRefresh = force) },
            loadBykc = { force -> bykcViewModel.ensureChosenCoursesLoaded(forceRefresh = force) },
            loadCgyy = { force -> cgyyViewModel?.ensureOrdersLoaded(forceRefresh = force) },
        ),
        forceRefresh = forceRefresh,
        showLoading = showLoading,
    )
  }

  fun refreshHomeData() {
    startHomeBootstrap(forceRefresh = true)
  }

  fun updateBykcCourseFilters(newFilters: BykcCourseFilters) {
    val shouldReloadCourses =
        bykcCourseFilters.requiresAllCourses() != newFilters.requiresAllCourses()
    bykcCourseFilters = newFilters
    if (newFilters == defaultBykcFilters) {
      BykcCourseFilterStore.clear(bykcFilterUserKey)
    } else {
      BykcCourseFilterStore.save(bykcFilterUserKey, newFilters.toStored())
    }
    if (shouldReloadCourses) {
      bykcViewModel.loadCourses(includeExpired = newFilters.requiresAllCourses())
    }
  }

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
              AppScreen.EVALUATION,
              AppScreen.YGDK_HOME,
              AppScreen.YGDK_FORM -> BottomNavTab.ADVANCED
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
            AppScreen.EVALUATION,
            AppScreen.YGDK_HOME,
            AppScreen.YGDK_FORM -> BottomNavTab.ADVANCED
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

  fun handleHomeTodoClick(todoItem: HomeTodoItem) {
    when (val action = todoItem.action) {
      is HomeTodoAction.OpenBykcCourse -> {
        selectedBykcCourseId = action.courseId
        selectedBykcCourseSnapshot = null
        bykcViewModel.loadCourseDetail(action.courseId)
        navigateTo(AppScreen.BYKC_DETAIL)
      }
      is HomeTodoAction.OpenSpocAssignment -> {
        selectedSpocAssignmentId = action.assignmentId
        spocViewModel.loadAssignmentDetail(action.assignmentId)
        navigateTo(AppScreen.SPOC_ASSIGNMENT_DETAIL)
      }
      HomeTodoAction.OpenCgyyOrders -> {
        cgyyViewModel?.ensureOrdersLoaded()
        navigateTo(AppScreen.CGYY_ORDERS)
      }
      is HomeTodoAction.SigninCourse -> signinViewModel.performSignin(action.courseId)
    }
  }

  LaunchedEffect(currentScreen) {
    if (currentScreen in cgyyScreens) {
      hasVisitedCgyy = true
    }
    if (currentScreen == AppScreen.MY) {
      onEnsureUserInfo()
    }
  }

  LaunchedEffect(currentScreen, shouldKeepCgyyViewModel) {
    if (currentScreen != AppScreen.HOME) {
      homeBootstrapCoordinator.cancel()
    }
    when (currentScreen) {
      AppScreen.HOME -> startHomeBootstrap()
      AppScreen.SCHEDULE -> scheduleViewModel.ensureScheduleLoaded()
      AppScreen.EXAM -> examViewModel?.ensureLoaded()
      AppScreen.BYKC_COURSES -> {
        bykcViewModel.ensureProfileLoaded()
        bykcViewModel.ensureCoursesLoaded(includeExpired = bykcCourseFilters.requiresAllCourses())
      }
      AppScreen.BYKC_CHOSEN -> bykcViewModel.ensureChosenCoursesLoaded()
      AppScreen.BYKC_STATISTICS -> bykcViewModel.ensureStatisticsLoaded()
      AppScreen.SIGNIN -> signinViewModel.ensureTodayLoaded()
      AppScreen.CGYY_HOME,
      AppScreen.CGYY_RESERVE_PICKER,
      AppScreen.CGYY_RESERVE_FORM -> {
        cgyyViewModel?.ensureInitialDataLoaded()
      }
      AppScreen.CGYY_ORDERS -> {
        cgyyViewModel?.ensureInitialDataLoaded()
        cgyyViewModel?.ensureOrdersLoaded()
      }
      AppScreen.CGYY_LOCK_CODE -> {
        cgyyViewModel?.ensureInitialDataLoaded()
        cgyyViewModel?.ensureLockCodeLoaded(forceRefresh = true)
      }
      AppScreen.EVALUATION -> evaluationViewModel?.ensureLoaded()
      AppScreen.SPOC_ASSIGNMENTS,
      AppScreen.SPOC_ASSIGNMENT_DETAIL -> spocViewModel.ensureAssignmentsLoaded()
      AppScreen.YGDK_HOME,
      AppScreen.YGDK_FORM -> ygdkViewModel?.ensureLoaded()
      else -> Unit
    }
  }

  LaunchedEffect(currentScreen, signinUiState.signinResult) {
    if (currentScreen == AppScreen.HOME) {
      signinUiState.signinResult?.let { message ->
        homeSnackbarHostState.showSnackbar(message)
        signinViewModel.clearSigninResult()
      }
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
        AppScreen.YGDK_HOME -> "阳光打卡"
        AppScreen.YGDK_FORM -> "新增打卡"
      }

  Box(modifier = modifier.fillMaxSize()) {
    BackHandlerCompat(enabled = showSidebar || navController.navStack.size > 1) {
      if (showSidebar) showSidebar = false else if (navController.navStack.size > 1) navigateBack()
    }

    Column(modifier = Modifier.fillMaxSize()) {
      val isRootScreen =
          currentScreen in listOf(AppScreen.HOME, AppScreen.REGULAR, AppScreen.ADVANCED)
      val showGlobalTopBar = currentScreen != AppScreen.SCHEDULE
      if (showGlobalTopBar) {
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
                            examViewModel?.selectTerm(it)
                            showExamTermMenu = false
                          },
                      )
                    }
                  }
                }
              } else if (currentScreen == AppScreen.SPOC_ASSIGNMENTS) {
                IconButton(onClick = { showSpocSortFilterDialog = true }) {
                  Icon(Icons.Default.Tune, contentDescription = "排序和筛选")
                }
              }
            },
        )
      }

      Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
        when (currentScreen) {
          AppScreen.HOME ->
              HomeScreen(
                  todayClasses = todayScheduleState.todayClasses,
                  isLoading = todayScheduleState.isLoading,
                  error = todayScheduleState.error,
                  todoItems = homeTodoItems,
                  todoLoading = homeTodoLoading,
                  todoFailedSources = homeTodoFailedSources,
                  signingTodoId =
                      signinUiState.signingInCourseId?.let { courseId -> "signin:$courseId" },
                  onRetrySchedule = { scheduleViewModel.loadTodaySchedule() },
                  onRefresh = { refreshHomeData() },
                  onTodoClick = { todoItem -> handleHomeTodoClick(todoItem) },
                  onSigninTodoClick = { courseId -> signinViewModel.performSignin(courseId) },
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
                  onYgdkClick = { navigateTo(AppScreen.YGDK_HOME) },
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
                  onNavigateBack = { navigateBack() },
                  onCourseClick = {
                    selectedCourse = it
                    navigateTo(AppScreen.COURSE_DETAIL)
                  },
              )
          AppScreen.EXAM -> examViewModel?.let { ExamScreen(viewModel = it) }
          AppScreen.COURSE_DETAIL -> selectedCourse?.let { CourseDetailScreen(course = it) }
          AppScreen.BYKC_HOME ->
              BykcHomeScreen(
                  onSelectCourseClick = { navigateTo(AppScreen.BYKC_COURSES) },
                  onMyCoursesClick = { navigateTo(AppScreen.BYKC_CHOSEN) },
                  onStatisticsClick = {
                    bykcViewModel.ensureStatisticsLoaded()
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
                  filters = bykcCourseFilters,
                  error = bykcCoursesState.error,
                  listState = bykcCoursesListState,
                  onCourseClick = {
                    selectedBykcCourseId = it.id
                    selectedBykcCourseSnapshot = it
                    bykcViewModel.loadCourseDetail(it.id)
                    navigateTo(AppScreen.BYKC_DETAIL)
                  },
                  onFiltersChange = ::updateBykcCourseFilters,
                  onRefresh = {
                    bykcViewModel.loadCourses(
                        includeExpired = bykcCourseFilters.requiresAllCourses()
                    )
                  },
                  onLoadMore = {
                    bykcViewModel.loadMoreCourses(
                        includeExpired = bykcCourseFilters.requiresAllCourses()
                    )
                  },
              )
          AppScreen.BYKC_DETAIL ->
              BykcCourseDetailScreen(
                  course = bykcDetailState.course,
                  listSnapshot = selectedBykcCourseSnapshot,
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
                    selectedBykcCourseSnapshot = null
                    bykcViewModel.loadCourseDetail(it.courseId)
                    navigateTo(AppScreen.BYKC_DETAIL)
                  },
                  onRefresh = { bykcViewModel.loadChosenCourses() },
              )
          AppScreen.CLASSROOM_QUERY ->
              classroomViewModel?.let {
                ClassroomQueryScreen(viewModel = it, onBackClick = { navigateBack() })
              }
          AppScreen.CGYY_HOME ->
              CgyyHomeScreen(
                  onReserveClick = { navigateTo(AppScreen.CGYY_RESERVE_PICKER) },
                  onOrdersClick = {
                    cgyyViewModel?.ensureOrdersLoaded()
                    navigateTo(AppScreen.CGYY_ORDERS)
                  },
                  onLockCodeClick = { navigateTo(AppScreen.CGYY_LOCK_CODE) },
              )
          AppScreen.CGYY_RESERVE_PICKER ->
              cgyyViewModel?.let {
                CgyyReservePickerScreen(
                    viewModel = it,
                    onNext = { navigateTo(AppScreen.CGYY_RESERVE_FORM) },
                )
              }
          AppScreen.CGYY_RESERVE_FORM ->
              cgyyViewModel?.let {
                CgyyReserveFormScreen(
                    viewModel = it,
                    onBackToSelection = { navigateBack() },
                    onSubmitSuccess = { navigateTo(AppScreen.CGYY_ORDERS) },
                )
              }
          AppScreen.CGYY_ORDERS -> cgyyViewModel?.let { CgyyOrdersScreen(viewModel = it) }
          AppScreen.CGYY_LOCK_CODE -> cgyyViewModel?.let { CgyyLockCodeScreen(viewModel = it) }
          AppScreen.EVALUATION -> evaluationViewModel?.let { EvaluationScreen(viewModel = it) }
          AppScreen.YGDK_HOME ->
              ygdkViewModel?.let {
                YgdkHomeScreen(
                    uiState = ygdkUiState,
                    onRefresh = { it.refreshAll() },
                    onLoadMore = { it.loadMoreRecords() },
                    onAddClick = { navigateTo(AppScreen.YGDK_FORM) },
                    onMessageConsumed = { it.clearSubmitMessage() },
                )
              }
          AppScreen.YGDK_FORM ->
              ygdkViewModel?.let { viewModel ->
                YgdkClockinFormScreen(
                    uiState = ygdkUiState,
                    imagePicker =
                        cn.edu.ubaa.ui.common.util.rememberPlatformImagePicker(
                            onImagePicked = { viewModel.setPhoto(it) },
                            onError = { viewModel.showMessage(it) },
                        ),
                    onItemSelected = { viewModel.updateItemId(it) },
                    onStartTimeChange = { viewModel.updateStartTime(it) },
                    onEndTimeChange = { viewModel.updateEndTime(it) },
                    onPlaceChange = { viewModel.updatePlace(it) },
                    onShareChange = { viewModel.setShareToSquare(it) },
                    onClearPhoto = { viewModel.clearPhoto() },
                    onSubmit = { viewModel.submitClockin { navigateBack() } },
                )
              }
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
                  AppScreen.YGDK_HOME,
                  AppScreen.YGDK_FORM,
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

    if (currentScreen == AppScreen.HOME) {
      SnackbarHost(
          hostState = homeSnackbarHostState,
          modifier =
              Modifier.align(Alignment.BottomCenter).padding(horizontal = 16.dp, vertical = 88.dp),
      )
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
