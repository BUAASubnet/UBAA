package cn.edu.ubaa.ui.screens

import androidx.compose.foundation.layout.*
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
import androidx.compose.ui.unit.dp

@Composable
fun BykcHomeScreen(
    onSelectCourseClick: () -> Unit,
    onMyCoursesClick: () -> Unit,
    onStatisticsClick: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        BykcFeatureCard(
            title = "选择课程",
            description = "浏览可选博雅课程，进行选课操作",
            icon = Icons.Default.List,
            onClick = onSelectCourseClick
        )

        BykcFeatureCard(
            title = "我的课程",
            description = "查看已选课程状态，签到/签退",
            icon = Icons.Default.Book,
            onClick = onMyCoursesClick
        )

        BykcFeatureCard(
            title = "课程统计",
            description = "查看博雅课程学时统计和达标情况",
            icon = Icons.Default.BarChart,
            onClick = onStatisticsClick
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BykcFeatureCard(
    title: String,
    description: String,
    icon: ImageVector,
    onClick: () -> Unit
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
    ) {
        Row(
            modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.width(24.dp))
            Column {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = description,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
