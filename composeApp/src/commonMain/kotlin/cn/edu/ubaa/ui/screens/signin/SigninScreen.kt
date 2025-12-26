package cn.edu.ubaa.ui.screens.signin

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.SigninClassDto

/**
 * 课堂签到主界面。
 * 展示今日课程列表并提供一键签到按钮。
 */
@Composable
fun SigninScreen(viewModel: SigninViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.signinResult) {
        uiState.signinResult?.let { snackbarHostState.showSnackbar(it); viewModel.clearSigninResult() }
    }

    Scaffold(
            snackbarHost = { SnackbarHost(snackbarHostState) },
            floatingActionButton = {
                FloatingActionButton(onClick = { viewModel.loadTodayClasses() }) { Icon(Icons.Default.Refresh, "刷新") }
            }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            Text(text = "课程签到", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold, modifier = Modifier.padding(bottom = 16.dp))

            when {
                uiState.isLoading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator() }
                uiState.error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) { Text(text = uiState.error!!, color = MaterialTheme.colorScheme.error) }
                uiState.classes.isEmpty() -> Box(Modifier.fillMaxSize(), Alignment.Center) { Text("今日无课程安排") }
                else -> {
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxSize()) {
                        items(uiState.classes) { clazz ->
                            SigninClassCard(clazz, { viewModel.performSignin(clazz.courseId) }, uiState.signingInCourseId == clazz.courseId)
                        }
                    }
                }
            }
        }
    }
}

/** 单个签到课程卡片。 */
@Composable
fun SigninClassCard(clazz: SigninClassDto, onSigninClick: () -> Unit, isSigningIn: Boolean) {
    val isSigned = clazz.signStatus == 1
    Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = if (isSigned) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant),
            elevation = CardDefaults.cardElevation(2.dp)
    ) {
        Row(modifier = Modifier.padding(20.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = clazz.courseName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.AccessTime, null, Modifier.size(14.dp), MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(text = "${clazz.classBeginTime} - ${clazz.classEndTime}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            if (isSigned) Icon(Icons.Default.CheckCircle, "已签到", Modifier.size(32.dp), MaterialTheme.colorScheme.primary)
            else Button(onClick = onSigninClick, enabled = !isSigningIn) {
                if (isSigningIn) CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary
                )
                else Text("签到")
            }
        }
    }
}