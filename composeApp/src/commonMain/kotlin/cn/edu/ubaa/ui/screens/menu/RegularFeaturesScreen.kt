package cn.edu.ubaa.ui.screens.menu

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Assignment
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.School
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

data class FeatureItem(
        val id: String,
        val title: String,
        val description: String,
        val icon: ImageVector
)

@Composable
fun RegularFeaturesScreen(
        onScheduleClick: () -> Unit,
        onExamClick: () -> Unit,
        onBykcClick: () -> Unit,
        onClassroomClick: () -> Unit,
        modifier: Modifier = Modifier
) {
        val features =
                listOf(
                        FeatureItem(
                                id = "schedule",
                                title = "课表查询",
                                description = "查看课程表，支持周视图和学期切换",
                                icon = Icons.Default.CalendarToday
                        ),
                        FeatureItem(
                                id = "exam",
                                title = "考试查询",
                                description = "查看考试安排，支持学期切换",
                                icon = Icons.AutoMirrored.Filled.Assignment
                        ),
                        FeatureItem(
                                id = "bykc",
                                title = "博雅课程",
                                description = "浏览选课，查看已选，签到签退",
                                icon = Icons.Default.School
                        ),
                        FeatureItem(
                                id = "classroom",
                                title = "空教室查询",
                                description = "查询各校区空闲教室",
                                icon = Icons.Default.MeetingRoom
                        )
                )

        Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
                Text(
                        text = "普通功能",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(bottom = 16.dp)
                )

                LazyVerticalGrid(
                        columns = GridCells.Fixed(2),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                        items(features) { feature ->
                                FeatureCard(
                                        feature = feature,
                                        onClick = {
                                                when (feature.id) {
                                                        "schedule" -> onScheduleClick()
                                                        "exam" -> onExamClick()
                                                        "bykc" -> onBykcClick()
                                                        "classroom" -> onClassroomClick()
                                                }
                                        }
                                )
                        }
                }
        }
}

@Composable
private fun FeatureCard(feature: FeatureItem, onClick: () -> Unit, modifier: Modifier = Modifier) {
        Card(
                modifier = modifier.fillMaxWidth().heightIn(min = 160.dp).clickable { onClick() },
                colors =
                        CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.surfaceVariant
                        ),
                elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
        ) {
                Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                ) {
                        Icon(
                                imageVector = feature.icon,
                                contentDescription = null,
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.primary
                        )

                        Spacer(modifier = Modifier.height(12.dp))

                        Text(
                                text = feature.title,
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                textAlign = TextAlign.Center
                        )

                        Spacer(modifier = Modifier.height(4.dp))

                        Text(
                                text = feature.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                textAlign = TextAlign.Center,
                                lineHeight = MaterialTheme.typography.bodySmall.lineHeight
                        )
                }
        }
}
