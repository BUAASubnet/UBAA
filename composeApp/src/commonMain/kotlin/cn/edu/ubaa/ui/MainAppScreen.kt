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
        
        // Don't close sidebar when navigating to MY or ABOUT screens
        // so users can return to the sidebar state
        if (screen !in listOf(AppScreen.MY, AppScreen.ABOUT)) {
            showSidebar = false
        }
    }
    
    fun navigateBack() {
        when (currentScreen) {
            AppScreen.MY, AppScreen.ABOUT -> {
                // Return to the previous screen with sidebar open
                currentScreen = AppScreen.HOME
                selectedBottomTab = BottomNavTab.HOME  
                showSidebar = true
            }
            AppScreen.COURSE_DETAIL -> navigateTo(AppScreen.SCHEDULE)
            AppScreen.SCHEDULE -> navigateTo(AppScreen.REGULAR, BottomNavTab.REGULAR)
            else -> {
                // Default back behavior for other screens
                currentScreen = AppScreen.HOME
                selectedBottomTab = BottomNavTab.HOME
                showSidebar = false
            }
        }
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
    
    Box(modifier = modifier.fillMaxSize()) {
        // Main content
        Column(
            modifier = Modifier.fillMaxSize()
        ) {
            // Unified Top app bar - always show but content varies by screen
            when (currentScreen) {
                AppScreen.MY, AppScreen.ABOUT -> {
                    TopAppBar(
                        title = { Text(screenTitle) },
                        navigationIcon = {
                            IconButton(onClick = { navigateBack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                            }
                        }
                    )
                }
                AppScreen.SCHEDULE -> {
                    TopAppBar(
                        title = { Text(screenTitle) },
                        navigationIcon = {
                            IconButton(onClick = { navigateBack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                            }
                        }
                    )
                }
                AppScreen.COURSE_DETAIL -> {
                    TopAppBar(
                        title = { Text(screenTitle) },
                        navigationIcon = {
                            IconButton(onClick = { navigateBack() }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
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
                            onBack = { navigateBack() }
                        )
                    }
                    
                    AppScreen.COURSE_DETAIL -> {
                        selectedCourse?.let { course ->
                            CourseDetailScreen(
                                course = course,
                                onBack = { navigateBack() }
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
        
        // Floating Sidebar - overlay on top of content with animation
        AnimatedVisibility(
            visible = showSidebar,
            enter = fadeIn() + slideInHorizontally(),
            exit = fadeOut() + slideOutHorizontally()
        ) {
            Box(
                modifier = Modifier.fillMaxSize()
            ) {
                // Semi-transparent backdrop with fade animation
                Box(
                    modifier = Modifier
                        .fillMaxSize()
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