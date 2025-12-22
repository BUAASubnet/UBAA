package cn.edu.ubaa.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.List
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

@Composable
fun BykcHomeScreen(
        onSelectCourseClick: () -> Unit,
        onMyCoursesClick: () -> Unit,
        onStatisticsClick: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize().padding(16.dp)) {
        Text(
                text = "博雅课程",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(bottom = 16.dp)
        )

        LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                BykcFeatureCard(
                        title = "选择课程",
                        description = "浏览可选博雅课程",
                        icon = Icons.Default.List,
                        onClick = onSelectCourseClick
                )
            }
            item {
                BykcFeatureCard(
                        title = "我的课程",
                        description = "查看已选/签到签退",
                        icon = Icons.Default.Book,
                        onClick = onMyCoursesClick
                )
            }
            item {
                BykcFeatureCard(
                        title = "课程统计",
                        description = "查看学时统计",
                        icon = Icons.Default.BarChart,
                        onClick = onStatisticsClick
                )
            }
        }
    }
}

@Composable
fun BykcFeatureCard(title: String, description: String, icon: ImageVector, onClick: () -> Unit) {
    Card(
            modifier = Modifier.fillMaxWidth().aspectRatio(1f).clickable { onClick() },
            elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
    ) {
        Column(
                modifier = Modifier.fillMaxSize().padding(16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
        ) {
            Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = MaterialTheme.colorScheme.primary
            )

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(4.dp))

            Text(
                    text = description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    lineHeight = MaterialTheme.typography.bodySmall.lineHeight
            )
        }
    }
}
