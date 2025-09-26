package cn.edu.ubaa.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import cn.edu.ubaa.model.dto.CourseClass
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import cn.edu.ubaa.ui.components.BottomNavigation
import cn.edu.ubaa.ui.components.BottomNavTab
import cn.edu.ubaa.ui.components.Sidebar
import cn.edu.ubaa.ui.screens.*

enum class AppScreen {
    HOME, REGULAR, ADVANCED, MY, ABOUT, SCHEDULE, COURSE_DETAIL
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainAppScreen(
    userData: UserData,
    userInfo: UserInfo?,
    onLogoutClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    var currentScreen by remember { mutableStateOf(AppScreen.HOME) }
    var selectedBottomTab by remember { mutableStateOf(BottomNavTab.HOME) }
    var showSidebar by remember { mutableStateOf(false) }
    
    val scheduleViewModel: ScheduleViewModel = viewModel()
    val scheduleUiState by scheduleViewModel.uiState.collectAsState()
    val todayScheduleState by scheduleViewModel.todayScheduleState.collectAsState()
    
    var selectedCourse by remember { mutableStateOf<CourseClass?>(null) }
    
    // Navigation logic
    fun navigateTo(screen: AppScreen, bottomTab: BottomNavTab? = null) {
        currentScreen = screen
        bottomTab?.let { selectedBottomTab = it }
        showSidebar = false
    }
    
    // Get current screen title
    val screenTitle = when (currentScreen) {
        AppScreen.HOME -> "首页"
        AppScreen.REGULAR -> "普通功能"
        AppScreen.ADVANCED -> "高级功能"
        AppScreen.MY -> "我的"
        AppScreen.ABOUT -> "关于"
        AppScreen.SCHEDULE -> "课程表"
        AppScreen.COURSE_DETAIL -> "课程详情"
    }
    
    Row(modifier = modifier.fillMaxSize()) {
        // Sidebar
        if (showSidebar) {
            Sidebar(
                userData = userData,
                onLogoutClick = onLogoutClick,
                onMyClick = { navigateTo(AppScreen.MY) },
                onAboutClick = { navigateTo(AppScreen.ABOUT) }
            )
        }
        
        // Main content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .weight(1f)
        ) {
            // Top app bar for screens that don't have their own
            if (currentScreen !in listOf(AppScreen.SCHEDULE, AppScreen.COURSE_DETAIL)) {
                TopAppBar(
                    title = { Text(screenTitle) },
                    navigationIcon = {
                        IconButton(onClick = { showSidebar = !showSidebar }) {
                            Icon(Icons.Default.Menu, contentDescription = "菜单")
                        }
                    }
                )
            }
            
            // Main content area
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
            ) {
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
                            onScheduleClick = { 
                                navigateTo(AppScreen.SCHEDULE)
                            }
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
                            onBack = { 
                                navigateTo(AppScreen.REGULAR, BottomNavTab.REGULAR)
                            }
                        )
                    }
                    
                    AppScreen.COURSE_DETAIL -> {
                        selectedCourse?.let { course ->
                            CourseDetailScreen(
                                course = course,
                                onBack = { navigateTo(AppScreen.SCHEDULE) }
                            )
                        }
                    }
                }
            }
            
            // Bottom navigation (hide for certain screens)
            if (currentScreen !in listOf(AppScreen.SCHEDULE, AppScreen.COURSE_DETAIL, AppScreen.MY, AppScreen.ABOUT)) {
                BottomNavigation(
                    currentTab = selectedBottomTab,
                    onTabSelected = { tab ->
                        when (tab) {
                            BottomNavTab.HOME -> navigateTo(AppScreen.HOME, tab)
                            BottomNavTab.REGULAR -> navigateTo(AppScreen.REGULAR, tab)
                            BottomNavTab.ADVANCED -> navigateTo(AppScreen.ADVANCED, tab)
                        }
                    }
                )
            }
        }
    }
}