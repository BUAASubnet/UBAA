package cn.edu.ubaa.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.CourseClass

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CourseDetailScreen(course: CourseClass, onBack: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxSize()) {
        // Top App Bar
        TopAppBar(
                title = { Text("课程详情") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                }
        )

        // Course details
        Column(
                modifier = Modifier.fillMaxSize().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Course name card
            Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors =
                            CardDefaults.cardColors(
                                    containerColor = MaterialTheme.colorScheme.primaryContainer
                            )
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                            text = course.courseName,
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                    )

                    Text(
                            text = "课程代码：${course.courseCode}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                    )
                }
            }

            // Course information
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                            text = "基本信息",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold
                    )

                    course.courseSerialNo?.let { serialNo -> CourseInfoRow("课程序号", serialNo) }

                    course.credit?.let { credit -> CourseInfoRow("学分", credit) }

                    course.placeName?.let { place -> CourseInfoRow("上课地点", place) }

                    if (course.beginTime != null && course.endTime != null) {
                        CourseInfoRow("上课时间", "${course.beginTime} - ${course.endTime}")
                    }

                    if (course.beginSection != null && course.endSection != null) {
                        val sectionText =
                                if (course.beginSection == course.endSection) {
                                    "第${course.beginSection}节"
                                } else {
                                    "第${course.beginSection}-${course.endSection}节"
                                }
                        CourseInfoRow("节次", sectionText)
                    }

                    course.dayOfWeek?.let { dayOfWeek ->
                        val dayName =
                                when (dayOfWeek) {
                                    1 -> "周一"
                                    2 -> "周二"
                                    3 -> "周三"
                                    4 -> "周四"
                                    5 -> "周五"
                                    6 -> "周六"
                                    7 -> "周日"
                                    else -> "未知"
                                }
                        CourseInfoRow("星期", dayName)
                    }
                }
            }

            // Additional information
            if (!course.weeksAndTeachers.isNullOrBlank() || !course.teachingTarget.isNullOrBlank()
            ) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                            modifier = Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(
                                text = "详细信息",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold
                        )

                        course.weeksAndTeachers?.let { weeksAndTeachers ->
                            CourseInfoRow("周次/教师", weeksAndTeachers)
                        }

                        course.teachingTarget?.let { teachingTarget ->
                            CourseInfoRow("教学对象", teachingTarget)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CourseInfoRow(label: String, value: String, modifier: Modifier = Modifier) {
    Row(modifier = modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(0.3f)
        )
        Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(0.7f)
        )
    }
}
