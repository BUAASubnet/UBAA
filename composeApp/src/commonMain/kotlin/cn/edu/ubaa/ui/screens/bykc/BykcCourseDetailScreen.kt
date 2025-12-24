package cn.edu.ubaa.ui.screens.bykc

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.*
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.BykcCourseDetailDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import kotlinx.coroutines.delay
import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BykcCourseDetailScreen(
        course: BykcCourseDetailDto?,
        isLoading: Boolean,
        error: String?,
        operationInProgress: Boolean,
        operationMessage: String?,
        onSelectClick: () -> Unit,
        onDeselectClick: () -> Unit,
        onSignInClick: () -> Unit,
        onSignOutClick: () -> Unit,
        onClearMessage: () -> Unit = {},
        modifier: Modifier = Modifier
) {
    when {
        isLoading -> {
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Spacer(modifier = Modifier.height(8.dp))
                    Text("加载课程详情...")
                }
            }
        }
        error != null -> {
            Box(
                    modifier = modifier.fillMaxSize().padding(16.dp),
                    contentAlignment = Alignment.Center
            ) { Text(text = "加载失败: $error", color = MaterialTheme.colorScheme.error) }
        }
        course != null -> {
            var now by remember { mutableStateOf(Clock.System.now()) }
            LaunchedEffect(Unit) {
                while (true) {
                    delay(5000)
                    now = Clock.System.now()
                }
            }

            val canSignIn =
                    remember(
                            course.signConfig?.signStartDate,
                            course.signConfig?.signEndDate,
                            now,
                            course.checkin
                    ) {
                        (course.checkin == 0 || course.checkin == null) &&
                                isWithinWindow(
                                        course.signConfig?.signStartDate,
                                        course.signConfig?.signEndDate
                                )
                    }
            val canSignOut =
                    remember(
                            course.signConfig?.signOutStartDate,
                            course.signConfig?.signOutEndDate,
                            now,
                            course.checkin
                    ) {
                        (course.checkin == 5 || course.checkin == 6) &&
                                isWithinWindow(
                                        course.signConfig?.signOutStartDate,
                                        course.signConfig?.signOutEndDate
                                )
                    }

            LazyColumn(
                    modifier = modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                item {
                    Card(
                            modifier = Modifier.fillMaxWidth(),
                            colors =
                                    CardDefaults.cardColors(
                                            containerColor =
                                                    MaterialTheme.colorScheme.primaryContainer
                                    )
                    ) {
                        Column(modifier = Modifier.padding(16.dp)) {
                            Text(
                                    text = course.courseName,
                                    style = MaterialTheme.typography.headlineSmall,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            CourseStatusChip(status = course.status, selected = course.selected)
                        }
                    }
                }

                item {
                    DetailCard(title = "基本信息") {
                        course.courseTeacher?.let { teacher ->
                            DetailItem(label = "授课教师", value = teacher, icon = Icons.Default.Person)
                        }
                        course.coursePosition?.let { position ->
                            DetailItem(label = "上课地点", value = position, icon = Icons.Default.Place)
                        }
                        course.category?.let { category ->
                            val categoryText =
                                    if (course.subCategory != null) {
                                        "$category / ${course.subCategory}"
                                    } else category
                            DetailItem(
                                    label = "课程分类",
                                    value = categoryText,
                                    icon = Icons.Default.Category
                            )
                        }
                    }
                }

                item {
                    DetailCard(title = "时间安排") {
                        course.courseStartDate?.let { startDate ->
                            course.courseEndDate?.let { endDate ->
                                DetailItem(
                                        label = "上课时间",
                                        value = formatDateRange(startDate, endDate),
                                        icon = Icons.Default.Event
                                )
                            }
                        }
                        course.courseSelectStartDate?.let { selectStart ->
                            course.courseSelectEndDate?.let { selectEnd ->
                                DetailItem(
                                        label = "选课时间",
                                        value = formatDateRange(selectStart, selectEnd),
                                        icon = Icons.Default.DateRange
                                )
                            }
                        }
                        course.courseCancelEndDate?.let { cancelEnd ->
                            DetailItem(
                                    label = "退选截止",
                                    value = cancelEnd.substringBefore(" 00:00:00"),
                                    icon = Icons.Default.Close
                            )
                        }
                    }
                }

                if (!course.courseContact.isNullOrBlank() ||
                                !course.courseContactMobile.isNullOrBlank()
                ) {
                    item {
                        DetailCard(title = "联系方式") {
                            course.courseContact?.let { contact ->
                                DetailItem(
                                        label = "联系人",
                                        value = contact,
                                        icon = Icons.Default.Person
                                )
                            }
                            course.courseContactMobile?.let { mobile ->
                                DetailItem(
                                        label = "联系电话",
                                        value = mobile,
                                        icon = Icons.Default.Phone
                                )
                            }
                        }
                    }
                }

                course.courseDesc?.takeIf { it.isNotBlank() }?.let { desc ->
                    item {
                        val parsedDesc = remember(desc) { desc.toPlainText() }
                        DetailCard(title = "课程简介") {
                            Text(
                                    text = parsedDesc,
                                    style = MaterialTheme.typography.bodyMedium,
                                    modifier = Modifier.padding(vertical = 8.dp)
                            )
                        }
                    }
                }

                course.signConfig?.let { config ->
                    item {
                        DetailCard(title = "签到信息") {
                            config.signStartDate?.let { signStart ->
                                config.signEndDate?.let { signEnd ->
                                    DetailItem(
                                            label = "签到时间",
                                            value = formatDateRange(signStart, signEnd),
                                            icon = Icons.AutoMirrored.Filled.Login
                                    )
                                }
                            }
                            config.signOutStartDate?.let { signOutStart ->
                                config.signOutEndDate?.let { signOutEnd ->
                                    DetailItem(
                                            label = "签退时间",
                                            value = formatDateRange(signOutStart, signOutEnd),
                                            icon = Icons.AutoMirrored.Filled.Logout
                                    )
                                }
                            }
                            if (config.signPoints.isNotEmpty()) {
                                DetailItem(
                                        label = "签到地点数",
                                        value = "${config.signPoints.size} 个",
                                        icon = Icons.Default.Place
                                )
                            }
                        }
                    }
                }

                item {
                    Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        if (course.selected) {
                            val showButtons = course.pass != 1 && course.signConfig != null
                            if (showButtons) {
                                Row(
                                        modifier = Modifier.fillMaxWidth(),
                                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                                ) {
                                    Button(
                                            onClick = onSignInClick,
                                            modifier = Modifier.weight(1f),
                                            enabled = !operationInProgress && canSignIn
                                    ) {
                                        Icon(
                                                Icons.AutoMirrored.Filled.Login,
                                                contentDescription = null
                                        )
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text("签到")
                                    }

                                    Button(
                                            onClick = onSignOutClick,
                                            modifier = Modifier.weight(1f),
                                            enabled = !operationInProgress && canSignOut
                                    ) {
                                        Icon(
                                                Icons.AutoMirrored.Filled.Logout,
                                                contentDescription = null
                                        )
                                        Spacer(modifier = Modifier.width(8.dp))
                                        Text("签退")
                                    }
                                }

                                Text(
                                        text = "经纬度由系统在签到范围内随机生成，无需手动填写。",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                )

                                if (!canSignIn && !canSignOut) {
                                    val reason =
                                            when {
                                                course.checkin != 0 &&
                                                        course.checkin != null &&
                                                        course.checkin != 5 &&
                                                        course.checkin != 6 -> "当前考勤状态不可签到/签退。"
                                                else -> "当前不在签到/签退时间窗口内。"
                                            }
                                    Text(
                                            text = reason,
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.error
                                    )
                                }
                            } else if (course.signConfig != null) {
                                Text(
                                        text = "课程已考核完成，无需签到。",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                        fontWeight = FontWeight.Bold,
                                        modifier = Modifier.fillMaxWidth(),
                                        textAlign = TextAlign.Center
                                )
                            }

                            OutlinedButton(
                                    onClick = onDeselectClick,
                                    modifier = Modifier.fillMaxWidth(),
                                    enabled =
                                            !operationInProgress &&
                                                    course.status != BykcCourseStatus.EXPIRED,
                                    colors =
                                            ButtonDefaults.outlinedButtonColors(
                                                    contentColor = MaterialTheme.colorScheme.error
                                            )
                            ) {
                                Icon(Icons.Default.Close, contentDescription = null)
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("退选")
                            }
                        } else {
                            Button(
                                    onClick = onSelectClick,
                                    modifier = Modifier.fillMaxWidth(),
                                    enabled =
                                            !operationInProgress &&
                                                    course.status == BykcCourseStatus.AVAILABLE
                            ) {
                                Icon(Icons.Default.Check, contentDescription = null)
                                Spacer(modifier = Modifier.width(8.dp))
                                Text("选择课程")
                            }
                        }
                    }
                }
            }

            if (operationMessage != null) {
                LaunchedEffect(operationMessage) {
                    delay(2500)
                    onClearMessage()
                }
                Box(modifier = modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                    AssistChip(
                            onClick = onClearMessage,
                            label = { Text(operationMessage) },
                            leadingIcon = { Icon(Icons.Default.Info, contentDescription = null) }
                    )
                }
            }
        }
    }
}

private fun isWithinWindow(start: String?, end: String?): Boolean {
    if (start.isNullOrBlank() || end.isNullOrBlank()) return false
    return try {
        val startDt = LocalDateTime.parse(start.replace(" ", "T"))
        val endDt = LocalDateTime.parse(end.replace(" ", "T"))
        val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        now >= startDt && now <= endDt
    } catch (_: Exception) {
        false
    }
}

@Composable
fun DetailCard(
        title: String,
        modifier: Modifier = Modifier,
        content: @Composable ColumnScope.() -> Unit
) {
    Card(modifier = modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp)) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(12.dp))
            content()
        }
    }
}

@Composable
fun DetailItem(
        label: String,
        value: String,
        icon: ImageVector? = null,
        modifier: Modifier = Modifier
) {
    Row(
            modifier = modifier.fillMaxWidth().padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically
    ) {
        icon?.let {
            Icon(
                    imageVector = it,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
        }

        Column(modifier = Modifier.weight(1f)) {
            Text(
                    text = label,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                    text = value,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
            )
        }
    }
}

private fun String.toPlainText(): String {
    // Basic HTML-to-text cleanup for BYKC descriptions
    return this.replace(Regex("(?i)<br\\s*/?>"), "\n")
            .replace(Regex("(?i)</p>"), "\n\n")
            .replace(Regex("<[^>]+>"), "")
            .replace("&nbsp;", " ")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&amp;", "&")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .lines()
            .joinToString("\n") { it.trimEnd() }
            .replace(Regex("\n{3,}"), "\n\n")
            .trim()
}
