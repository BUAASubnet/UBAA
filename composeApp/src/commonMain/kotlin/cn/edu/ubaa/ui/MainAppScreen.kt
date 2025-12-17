package cn.edu.ubaa.ui

import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.model.dto.CourseClass
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
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
    COURSE_DETAIL,
    BYKC_COURSES,
    BYKC_DETAIL,
    BYKC_CHOSEN
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainAppScreen(
        userData: UserData,
        userInfo: UserInfo?,
        onLogoutClick: () -> Unit,
        modifier: Modifier = Modifier
) {
    val navStack = remember { mutableStateListOf(AppScreen.HOME) }
    val currentScreen by remember { derivedStateOf { navStack.last() } }
    var selectedBottomTab by remember { mutableStateOf(BottomNavTab.HOME) }
    var showSidebar by remember { mutableStateOf(false) }

    val scheduleViewModel: ScheduleViewModel = viewModel()
    val scheduleUiState by scheduleViewModel.uiState.collectAsState()
    val todayScheduleState by scheduleViewModel.todayScheduleState.collectAsState()

    // Key the BYKC VM by user id so switching accounts recreates state and reloads fresh data
    val bykcViewModel: BykcViewModel = viewModel(key = "bykc-${userData.schoolid}")
    val bykcCoursesState by bykcViewModel.coursesState.collectAsState()
    val bykcDetailState by bykcViewModel.courseDetailState.collectAsState()
    val bykcChosenState by bykcViewModel.chosenCoursesState.collectAsState()

    var selectedCourse by remember { mutableStateOf<CourseClass?>(null) }
    var selectedBykcCourseId by remember { mutableStateOf<Long?>(null) }
    var showBykcIncludeExpired by remember { mutableStateOf(false) }

    fun setRoot(screen: AppScreen, tab: BottomNavTab) {
        navStack.clear()
        navStack.add(screen)
        selectedBottomTab = tab
        showSidebar = false
    }

    // Navigation logic
    fun navigateTo(screen: AppScreen, bottomTab: BottomNavTab? = null) {
        if (navStack.lastOrNull() != screen) {
            navStack.add(screen)
        }

        val tab =
                bottomTab
                        ?: when (screen) {
                            AppScreen.HOME -> BottomNavTab.HOME
                            AppScreen.REGULAR, AppScreen.SCHEDULE, AppScreen.COURSE_DETAIL ->
                                    BottomNavTab.REGULAR
                            AppScreen.ADVANCED,
                            AppScreen.BYKC_COURSES,
                            AppScreen.BYKC_DETAIL,
                            AppScreen.BYKC_CHOSEN -> BottomNavTab.ADVANCED
                            else -> null
                        }
        tab?.let { selectedBottomTab = it }

        if (screen !in listOf(AppScreen.MY, AppScreen.ABOUT)) {
            showSidebar = false
        }
    }

    fun navigateBack() {
        if (navStack.size > 1) {
            navStack.removeLast()
            val top = navStack.last()
            val tab =
                    when (top) {
                        AppScreen.HOME -> BottomNavTab.HOME
                        AppScreen.REGULAR, AppScreen.SCHEDULE, AppScreen.COURSE_DETAIL ->
                                BottomNavTab.REGULAR
                        AppScreen.ADVANCED,
                        AppScreen.BYKC_COURSES,
                        AppScreen.BYKC_DETAIL,
                        AppScreen.BYKC_CHOSEN -> BottomNavTab.ADVANCED
                        else -> null
                    }
            tab?.let { selectedBottomTab = it }
            if (top in listOf(AppScreen.MY, AppScreen.ABOUT)) {
                showSidebar = true
            }
        } else {
            // already at root
            selectedBottomTab = BottomNavTab.HOME
            showSidebar = false
        }
    }

    // Get current screen title
    val screenTitle =
            when (currentScreen) {
                AppScreen.HOME -> "首页"
                AppScreen.REGULAR -> "普通功能"
                AppScreen.ADVANCED -> "高级功能"
                AppScreen.MY -> "我的"
                AppScreen.ABOUT -> "关于"
                AppScreen.SCHEDULE -> "课程表"
                AppScreen.COURSE_DETAIL -> "课程详情"
                AppScreen.BYKC_COURSES -> "博雅课程"
                AppScreen.BYKC_DETAIL -> "课程详情"
                AppScreen.BYKC_CHOSEN -> "已选课程"
            }

    Box(modifier = modifier.fillMaxSize()) {
        BackHandlerCompat(enabled = showSidebar || navStack.size > 1) {
            if (showSidebar) {
                showSidebar = false
            } else {
                navigateBack()
            }
        }

        // Main content
        Column(modifier = Modifier.fillMaxSize()) {
            // Unified Top app bar - always show but content varies by screen
            when (currentScreen) {
                AppScreen.MY, AppScreen.ABOUT -> {
                    TopAppBar(
                            title = { Text(screenTitle) },
                            navigationIcon = {
                                IconButton(onClick = { navigateBack() }) {
                                    Icon(
                                            Icons.AutoMirrored.Filled.ArrowBack,
                                            contentDescription = "返回"
                                    )
                                }
                            }
                    )
                }
                AppScreen.SCHEDULE -> {
                    TopAppBar(
                            title = { Text(screenTitle) },
                            navigationIcon = {
                                IconButton(onClick = { navigateBack() }) {
                                    Icon(
                                            Icons.AutoMirrored.Filled.ArrowBack,
                                            contentDescription = "返回"
                                    )
                                }
                            }
                    )
                }
                AppScreen.COURSE_DETAIL -> {
                    TopAppBar(
                            title = { Text(screenTitle) },
                            navigationIcon = {
                                IconButton(onClick = { navigateBack() }) {
                                    Icon(
                                            Icons.AutoMirrored.Filled.ArrowBack,
                                            contentDescription = "返回"
                                    )
                                }
                            }
                    )
                }
                AppScreen.BYKC_COURSES, AppScreen.BYKC_DETAIL, AppScreen.BYKC_CHOSEN -> {
                    TopAppBar(
                            title = { Text(screenTitle) },
                            navigationIcon = {
                                IconButton(onClick = { navigateBack() }) {
                                    Icon(
                                            Icons.AutoMirrored.Filled.ArrowBack,
                                            contentDescription = "返回"
                                    )
                                }
                            }
                    )
                }
                else -> {
                    TopAppBar(
                            title = { Text(screenTitle) },
                            navigationIcon = {
                                IconButton(onClick = { showSidebar = !showSidebar }) {
                                    Icon(Icons.Default.Menu, contentDescription = "菜单")
                                }
                            }
                    )
                }
            }

            // Main content area
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
                        RegularFeaturesScreen(onScheduleClick = { navigateTo(AppScreen.SCHEDULE) })
                    }
                    AppScreen.ADVANCED -> {
                        AdvancedFeaturesScreen(
                                onBykcCoursesClick = { navigateTo(AppScreen.BYKC_COURSES) },
                                onBykcChosenClick = { navigateTo(AppScreen.BYKC_CHOSEN) }
                        )
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
                    AppScreen.COURSE_DETAIL -> {
                        selectedCourse?.let { course ->
                            CourseDetailScreen(course = course, onBack = { navigateBack() })
                        }
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
                                    // 使用 courseId (课程ID) 而不是 id (选课记录ID) 来查询课程详情
                                    selectedBykcCourseId = course.courseId
                                    bykcViewModel.loadCourseDetail(course.courseId)
                                    navigateTo(AppScreen.BYKC_DETAIL)
                                },
                                onRefresh = { bykcViewModel.loadChosenCourses() }
                        )
                    }
                }
            }

            // Bottom navigation (hide for certain screens)
            if (currentScreen !in
                            listOf(
                                    AppScreen.SCHEDULE,
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

        // Floating Sidebar - overlay on top of content with animation
        AnimatedVisibility(
                visible = showSidebar,
                enter = fadeIn() + slideInHorizontally(),
                exit = fadeOut() + slideOutHorizontally()
        ) {
            Box(modifier = Modifier.fillMaxSize()) {
                // Semi-transparent backdrop with fade animation
                Box(
                        modifier =
                                Modifier.fillMaxSize()
                                        .background(Color.Black.copy(alpha = 0.5f))
                                        .clickable { showSidebar = false }
                )

                // Sidebar with slide animation
                Sidebar(
                        userData = userData,
                        onLogoutClick = onLogoutClick,
                        onMyClick = { navigateTo(AppScreen.MY) },
                        onAboutClick = { navigateTo(AppScreen.ABOUT) },
                        modifier = Modifier.align(Alignment.CenterStart)
                )
            }
        }
    }
}
