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

@Composable
fun SigninScreen(viewModel: SigninViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(uiState.signinResult) {
        uiState.signinResult?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearSigninResult()
        }
    }

    Scaffold(
            snackbarHost = { SnackbarHost(snackbarHostState) },
            floatingActionButton = {
                FloatingActionButton(onClick = { viewModel.loadTodayClasses() }) {
                    Icon(Icons.Default.Refresh, contentDescription = "刷新")
                }
            }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp)) {
            Text(
                    text = "课程签到",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(bottom = 16.dp)
            )

            if (uiState.isLoading) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else if (uiState.error != null) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(text = uiState.error!!, color = MaterialTheme.colorScheme.error)
                }
            } else if (uiState.classes.isEmpty()) {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(text = "今日无课程安排")
                }
            } else {
                LazyColumn(
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                        modifier = Modifier.fillMaxSize()
                ) {
                    items(uiState.classes) { clazz ->
                        SigninClassCard(
                                clazz = clazz,
                                onSigninClick = { viewModel.performSignin(clazz.courseId) },
                                isSigningIn = uiState.signingInCourseId == clazz.courseId
                        )
                    }

                    item {
                        Spacer(modifier = Modifier.height(8.dp))
                        OutlinedButton(
                                onClick = { viewModel.loadTodayClasses() },
                                modifier = Modifier.fillMaxWidth()
                        ) {
                            Icon(Icons.Default.Refresh, contentDescription = null)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("刷新课程")
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SigninClassCard(clazz: SigninClassDto, onSigninClick: () -> Unit, isSigningIn: Boolean) {
    val isSigned = clazz.signStatus == 1

    Card(
            modifier = Modifier.fillMaxWidth(),
            colors =
                    CardDefaults.cardColors(
                            containerColor =
                                    if (isSigned) MaterialTheme.colorScheme.primaryContainer
                                    else MaterialTheme.colorScheme.surfaceVariant
                    ),
            elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Row(
                modifier = Modifier.padding(20.dp).fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                        text = clazz.courseName,
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                            imageVector = Icons.Default.AccessTime,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                            text = "${clazz.classBeginTime} - ${clazz.classEndTime}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            if (isSigned) {
                Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = "已签到",
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(32.dp)
                )
            } else {
                Button(
                        onClick = onSigninClick,
                        enabled = !isSigningIn,
                        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                ) {
                    if (isSigningIn) {
                        SizedCircularProgressIndicator()
                    } else {
                        Text("签到")
                    }
                }
            }
        }
    }
}

@Composable
fun SizedCircularProgressIndicator() {
    CircularProgressIndicator(
            modifier = Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.onPrimary
    )
}
