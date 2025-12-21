package cn.edu.ubaa.ui

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.model.dto.CourseClass
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import cn.edu.ubaa.ui.components.AppTopBar
import cn.edu.ubaa.ui.components.BottomNavTab
import cn.edu.ubaa.ui.components.BottomNavigation
import cn.edu.ubaa.ui.components.Sidebar
import cn.edu.ubaa.ui.screens.*
import cn.edu.ubaa.ui.util.BackHandlerCompat

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
    BYKC_STATISTICS
}

// 主界面入口
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainAppScreen(
        userData: UserData,
        userInfo: UserInfo?,
        onLogoutClick: () -> Unit,
        modifier: Modifier = Modifier
) {
    val navController = rememberNavigationController()
    val currentScreen =
    // 导航栈变化时重组界面
    navController.currentScreen

    var selectedBottomTab by remember { mutableStateOf(BottomNavTab.HOME) }
    var showSidebar by remember { mutableStateOf(false) }

    val scheduleViewModel: ScheduleViewModel = viewModel()
    val scheduleUiState by scheduleViewModel.uiState.collectAsState()
    val todayScheduleState by scheduleViewModel.todayScheduleState.collectAsState()

    val examViewModel: ExamViewModel = viewModel()
    val examUiState by examViewModel.uiState.collectAsState()
    var showExamTermMenu by remember { mutableStateOf(false) }

    // 以用户ID为key，切换账号时重建并刷新BYKC VM
    val bykcViewModel: BykcViewModel = viewModel(key = "bykc-${userData.schoolid}")
    val bykcCoursesState by bykcViewModel.coursesState.collectAsState()
    val bykcDetailState by bykcViewModel.courseDetailState.collectAsState()
    val bykcChosenState by bykcViewModel.chosenCoursesState.collectAsState()

    var selectedCourse by remember { mutableStateOf<CourseClass?>(null) }
    var selectedBykcCourseId by remember { mutableStateOf<Long?>(null) }
    var showBykcIncludeExpired by remember { mutableStateOf(false) }

    fun setRoot(screen: AppScreen, tab: BottomNavTab) {
        navController.setRoot(screen)
        selectedBottomTab = tab
        showSidebar = false
    }

    // 导航逻辑
    fun navigateTo(screen: AppScreen, bottomTab: BottomNavTab? = null) {
        navController.navigateTo(screen)

        val tab =
                bottomTab
                        ?: when (screen) {
                            AppScreen.HOME -> BottomNavTab.HOME
                            AppScreen.REGULAR,
                            AppScreen.SCHEDULE,
                            AppScreen.EXAM,
                            AppScreen.COURSE_DETAIL -> BottomNavTab.REGULAR
                            AppScreen.ADVANCED,
                            AppScreen.BYKC_HOME,
                            AppScreen.BYKC_COURSES,
                            AppScreen.BYKC_DETAIL,
                            AppScreen.BYKC_CHOSEN,
                            AppScreen.BYKC_STATISTICS -> BottomNavTab.ADVANCED
                            else -> null
                        }
        tab?.let { selectedBottomTab = it }

        if (screen !in listOf(AppScreen.MY, AppScreen.ABOUT)) {
            showSidebar = false
        }
    }

    fun navigateBack() {
        if (navController.navigateBack()) {
            val top = navController.currentScreen
            val tab =
                    when (top) {
                        AppScreen.HOME -> BottomNavTab.HOME
                        AppScreen.REGULAR,
                        AppScreen.SCHEDULE,
                        AppScreen.EXAM,
                        AppScreen.COURSE_DETAIL -> BottomNavTab.REGULAR
                        AppScreen.ADVANCED,
                        AppScreen.BYKC_HOME,
                        AppScreen.BYKC_COURSES,
                        AppScreen.BYKC_DETAIL,
                        AppScreen.BYKC_CHOSEN,
                        AppScreen.BYKC_STATISTICS -> BottomNavTab.ADVANCED
                        else -> null
                    }
            tab?.let { selectedBottomTab = it }
            if (top in listOf(AppScreen.MY, AppScreen.ABOUT)) {
                showSidebar = true
            }
        } else {
            // 已在根页面，重置底栏和侧边栏
            selectedBottomTab = BottomNavTab.HOME
            showSidebar = false
        }
    }

    // 获取当前页面标题
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
            }

    Box(modifier = modifier.fillMaxSize()) {
        BackHandlerCompat(enabled = showSidebar || navController.navStack.size > 1) {
            if (showSidebar) {
                showSidebar = false
            } else {
                navigateBack()
            }
        }

        // 主内容区域
        Column(modifier = Modifier.fillMaxSize()) {
            // 顶部导航栏统一处理
            val isRootScreen =
                    currentScreen in listOf(AppScreen.HOME, AppScreen.REGULAR, AppScreen.ADVANCED)

            AppTopBar(
                    title = screenTitle,
                    canNavigateBack = !isRootScreen,
                    onNavigationIconClick = {
                        if (isRootScreen) {
                            showSidebar = !showSidebar
                        } else {
                            navigateBack()
                        }
                    },
                    actions = {
                        if (currentScreen == AppScreen.EXAM) {
                            Box {
                                TextButton(onClick = { showExamTermMenu = true }) {
                                    Text(examUiState.selectedTerm?.itemName ?: "选择学期")
                                    Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                                }
                                DropdownMenu(
                                        expanded = showExamTermMenu,
                                        onDismissRequest = { showExamTermMenu = false }
                                ) {
                                    examUiState.terms.forEach { term ->
                                        DropdownMenuItem(
                                                text = { Text(term.itemName) },
                                                onClick = {
                                                    examViewModel.selectTerm(term)
                                                    showExamTermMenu = false
                                                }
                                        )
                                    }
                                }
                            }
                        }
                    }
            )

            // 主内容区，根据当前页面切换
            Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
                when (currentScreen) {
                    AppScreen.HOME -> {
                        HomeScreen(
                                todayClasses = todayScheduleState.todayClasses,
                                isLoading = todayScheduleState.isLoading,
                                error = todayScheduleState.error,
                                onRefresh = { scheduleViewModel.loadTodaySchedule() }
                        )
                    }
                    AppScreen.REGULAR -> {
                        RegularFeaturesScreen(
                                onScheduleClick = { navigateTo(AppScreen.SCHEDULE) },
                                onExamClick = { navigateTo(AppScreen.EXAM) },
                                onBykcClick = { navigateTo(AppScreen.BYKC_HOME) }
                        )
                    }
                    AppScreen.ADVANCED -> {
                        AdvancedFeaturesScreen()
                    }
                    AppScreen.MY -> {
                        MyScreen()
                    }
                    AppScreen.ABOUT -> {
                        AboutScreen()
                    }
                    AppScreen.SCHEDULE -> {
                        ScheduleScreen(
                                terms = scheduleUiState.terms,
                                weeks = scheduleUiState.weeks,
                                weeklySchedule = scheduleUiState.weeklySchedule,
                                selectedTerm = scheduleUiState.selectedTerm,
                                selectedWeek = scheduleUiState.selectedWeek,
                                isLoading = scheduleUiState.isLoading,
                                error = scheduleUiState.error,
                                onTermSelected = { term -> scheduleViewModel.selectTerm(term) },
                                onWeekSelected = { week -> scheduleViewModel.selectWeek(week) },
                                onCourseClick = { course ->
                                    selectedCourse = course
                                    navigateTo(AppScreen.COURSE_DETAIL)
                                },
                                onBack = { navigateBack() }
                        )
                    }
                    AppScreen.EXAM -> {
                        ExamScreen(viewModel = examViewModel)
                    }
                    AppScreen.COURSE_DETAIL -> {
                        selectedCourse?.let { course ->
                            CourseDetailScreen(course = course, onBack = { navigateBack() })
                        }
                    }
                    AppScreen.BYKC_HOME -> {
                        BykcHomeScreen(
                                onSelectCourseClick = { navigateTo(AppScreen.BYKC_COURSES) },
                                onMyCoursesClick = { navigateTo(AppScreen.BYKC_CHOSEN) },
                                onStatisticsClick = {
                                    bykcViewModel.loadStatistics()
                                    navigateTo(AppScreen.BYKC_STATISTICS)
                                }
                        )
                    }
                    AppScreen.BYKC_STATISTICS -> {
                        BykcStatisticsScreen(viewModel = bykcViewModel)
                    }
                    AppScreen.BYKC_COURSES -> {
                        BykcCoursesScreen(
                                courses = bykcCoursesState.courses,
                                isLoading = bykcCoursesState.isLoading,
                                error = bykcCoursesState.error,
                                onCourseClick = { course ->
                                    selectedBykcCourseId = course.id
                                    bykcViewModel.loadCourseDetail(course.id)
                                    navigateTo(AppScreen.BYKC_DETAIL)
                                },
                                onRefresh = {
                                    bykcViewModel.loadCourses(
                                            includeExpired = showBykcIncludeExpired
                                    )
                                },
                                includeExpired = showBykcIncludeExpired,
                                onIncludeExpiredChange = { include ->
                                    showBykcIncludeExpired = include
                                    bykcViewModel.loadCourses(includeExpired = include)
                                }
                        )
                    }
                    AppScreen.BYKC_DETAIL -> {
                        BykcCourseDetailScreen(
                                course = bykcDetailState.course,
                                isLoading = bykcDetailState.isLoading,
                                error = bykcDetailState.error,
                                operationInProgress = bykcDetailState.operationInProgress,
                                operationMessage = bykcDetailState.operationMessage,
                                onSelectClick = {
                                    selectedBykcCourseId?.let { courseId ->
                                        bykcViewModel.selectCourse(courseId) { _, _ -> }
                                    }
                                },
                                onDeselectClick = {
                                    selectedBykcCourseId?.let { courseId ->
                                        bykcViewModel.deselectCourse(courseId) { _, _ -> }
                                    }
                                },
                                onSignInClick = {
                                    selectedBykcCourseId?.let { courseId ->
                                        bykcViewModel.signCourse(courseId, null, null, 1) { _, _ ->
                                        }
                                    }
                                },
                                onSignOutClick = {
                                    selectedBykcCourseId?.let { courseId ->
                                        bykcViewModel.signCourse(courseId, null, null, 2) { _, _ ->
                                        }
                                    }
                                },
                                onClearMessage = { bykcViewModel.clearOperationMessage() }
                        )
                    }
                    AppScreen.BYKC_CHOSEN -> {
                        BykcChosenCoursesScreen(
                                courses = bykcChosenState.courses,
                                isLoading = bykcChosenState.isLoading,
                                error = bykcChosenState.error,
                                onCourseClick = { course ->
                                    // 选课详情用 courseId 查询，避免混淆
                                    selectedBykcCourseId = course.courseId
                                    bykcViewModel.loadCourseDetail(course.courseId)
                                    navigateTo(AppScreen.BYKC_DETAIL)
                                },
                                onRefresh = { bykcViewModel.loadChosenCourses() }
                        )
                    }
                }
            }

            // 底部导航栏（部分页面隐藏）
            if (currentScreen !in
                            listOf(
                                    AppScreen.SCHEDULE,
                                    AppScreen.EXAM,
                                    AppScreen.COURSE_DETAIL,
                                    AppScreen.MY,
                                    AppScreen.ABOUT,
                                    AppScreen.BYKC_COURSES,
                                    AppScreen.BYKC_DETAIL,
                                    AppScreen.BYKC_CHOSEN
                            )
            ) {
                BottomNavigation(
                        currentTab = selectedBottomTab,
                        onTabSelected = { tab ->
                            when (tab) {
                                BottomNavTab.HOME -> setRoot(AppScreen.HOME, BottomNavTab.HOME)
                                BottomNavTab.REGULAR ->
                                        setRoot(AppScreen.REGULAR, BottomNavTab.REGULAR)
                                BottomNavTab.ADVANCED ->
                                        setRoot(AppScreen.ADVANCED, BottomNavTab.ADVANCED)
                            }
                        }
                )
            }
        }

        // 浮动侧边栏，带动画覆盖内容
        AnimatedVisibility(visible = showSidebar, enter = fadeIn(), exit = fadeOut()) {
            // 半透明背景，点击关闭侧边栏
            Box(
                    modifier =
                            Modifier.fillMaxSize()
                                    .background(Color.Black.copy(alpha = 0.5f))
                                    .clickable { showSidebar = false }
            )
        }

        AnimatedVisibility(
                visible = showSidebar,
                // 仅让侧边栏自身滑动，避免整屏参与动画导致掉帧
                enter = slideInHorizontally(),
                // 退出时滑出视窗外再移除，避免“滑一截然后瞬移”
                exit = slideOutHorizontally(targetOffsetX = { -it * 2 })
        ) {
            Box(modifier = Modifier.fillMaxHeight(), contentAlignment = Alignment.CenterStart) {
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
                        modifier = Modifier.align(Alignment.CenterStart)
                )
            }
        }
    }
}
