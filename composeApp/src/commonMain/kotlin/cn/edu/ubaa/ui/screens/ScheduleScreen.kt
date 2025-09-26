package cn.edu.ubaa.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.edu.ubaa.model.dto.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScheduleScreen(
    terms: List<Term>,
    weeks: List<Week>,
    weeklySchedule: WeeklySchedule?,
    selectedTerm: Term?,
    selectedWeek: Week?,
    isLoading: Boolean,
    error: String?,
    onTermSelected: (Term) -> Unit,
    onWeekSelected: (Week) -> Unit,
    onCourseClick: (CourseClass) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier = Modifier
) {
    var showTermDropdown by remember { mutableStateOf(false) }
    
    Column(
        modifier = modifier.fillMaxSize()
    ) {
        // Top App Bar
        TopAppBar(
            title = { Text("课程表") },
            navigationIcon = {
                IconButton(onClick = onBack) {
                    Icon(Icons.Default.ArrowBack, contentDescription = "返回")
                }
            }
        )
        
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp)
        ) {
            // Term Selector
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "学期：",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium
                )
                
                Spacer(modifier = Modifier.width(8.dp))
                
                ExposedDropdownMenuBox(
                    expanded = showTermDropdown,
                    onExpandedChange = { showTermDropdown = !showTermDropdown }
                ) {
                    OutlinedTextField(
                        value = selectedTerm?.itemName ?: "选择学期",
                        onValueChange = {},
                        readOnly = true,
                        trailingIcon = {
                            Icon(Icons.Default.ArrowDropDown, contentDescription = null)
                        },
                        modifier = Modifier
                            .menuAnchor()
                            .weight(1f)
                    )
                    
                    ExposedDropdownMenu(
                        expanded = showTermDropdown,
                        onDismissRequest = { showTermDropdown = false }
                    ) {
                        terms.forEach { term ->
                            DropdownMenuItem(
                                text = { Text(term.itemName) },
                                onClick = {
                                    onTermSelected(term)
                                    showTermDropdown = false
                                }
                            )
                        }
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // Week Selector (if weeks available)
            if (weeks.isNotEmpty()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "周次：",
                        style = MaterialTheme.typography.bodyLarge,
                        fontWeight = FontWeight.Medium
                    )
                    
                    Spacer(modifier = Modifier.width(8.dp))
                    
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(weeks) { week ->
                            WeekChip(
                                week = week,
                                isSelected = week == selectedWeek,
                                onClick = { onWeekSelected(week) }
                            )
                        }
                    }
                }
                
                Spacer(modifier = Modifier.height(16.dp))
            }
            
            // Schedule Content
            when {
                isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            CircularProgressIndicator()
                            Spacer(modifier = Modifier.height(8.dp))
                            Text("加载课程表...")
                        }
                    }
                }
                
                error != null -> {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(
                            containerColor = MaterialTheme.colorScheme.errorContainer
                        )
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(
                                text = "加载失败",
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.onErrorContainer
                            )
                            Spacer(modifier = Modifier.height(4.dp))
                            Text(
                                text = error,
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onErrorContainer
                            )
                        }
                    }
                }
                
                weeklySchedule != null -> {
                    WeeklyScheduleView(
                        schedule = weeklySchedule,
                        onCourseClick = onCourseClick,
                        modifier = Modifier.fillMaxSize()
                    )
                }
                
                else -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "请选择学期和周次",
                            style = MaterialTheme.typography.bodyLarge,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun WeekChip(
    week: Week,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    FilterChip(
        selected = isSelected,
        onClick = onClick,
        label = { Text(week.name) },
        modifier = modifier,
        border = if (week.curWeek && !isSelected) {
            FilterChipDefaults.filterChipBorder(
                enabled = true,
                selected = false,
                borderColor = MaterialTheme.colorScheme.primary,
                borderWidth = 2.dp
            )
        } else null
    )
}

@Composable
private fun WeeklyScheduleView(
    schedule: WeeklySchedule,
    onCourseClick: (CourseClass) -> Unit,
    modifier: Modifier = Modifier
) {
    val daysOfWeek = listOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
    val timeSlots = (1..12).toList() // Assuming 12 time slots per day
    
    LazyColumn(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        // Header row with days
        item {
            Row(modifier = Modifier.fillMaxWidth()) {
                // Time column header
                Box(
                    modifier = Modifier
                        .width(50.dp)
                        .height(40.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant,
                            RoundedCornerShape(4.dp)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "节次",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                
                // Day headers
                for (day in daysOfWeek) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(40.dp)
                            .padding(horizontal = 1.dp)
                            .background(
                                MaterialTheme.colorScheme.surfaceVariant,
                                RoundedCornerShape(4.dp)
                            ),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = day,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }
                }
            }
        }
        
        // Schedule grid
        items(timeSlots) { timeSlot ->
            Row(modifier = Modifier.fillMaxWidth()) {
                // Time slot label
                Box(
                    modifier = Modifier
                        .width(50.dp)
                        .height(60.dp)
                        .background(
                            MaterialTheme.colorScheme.surfaceVariant,
                            RoundedCornerShape(4.dp)
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "$timeSlot",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium
                    )
                }
                
                // Day columns
                for (dayOfWeek in 1..7) {
                    val coursesForSlot = schedule.arrangedList.filter { course ->
                        course.dayOfWeek == dayOfWeek && 
                        (course.beginSection ?: 0) <= timeSlot && 
                        timeSlot <= (course.endSection ?: 0)
                    }
                    
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(60.dp)
                            .padding(horizontal = 1.dp)
                    ) {
                        if (coursesForSlot.isNotEmpty()) {
                            val course = coursesForSlot.first()
                            CourseCell(
                                course = course,
                                onClick = { onCourseClick(course) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CourseCell(
    course: CourseClass,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier
            .fillMaxSize()
            .clickable { onClick() },
        colors = CardDefaults.cardColors(
            containerColor = parseColor(course.color) ?: MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(4.dp),
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = course.courseName,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center
            )
            
            course.placeName?.let { place ->
                Text(
                    text = place,
                    fontSize = 8.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

private fun parseColor(colorString: String?): Color? {
    // Simple hex color parsing for multiplatform compatibility
    return try {
        colorString?.let { 
            if (it.startsWith("#") && it.length == 7) {
                val hex = it.substring(1)
                val r = hex.substring(0, 2).toInt(16) / 255f
                val g = hex.substring(2, 4).toInt(16) / 255f
                val b = hex.substring(4, 6).toInt(16) / 255f
                Color(r, g, b, 1f)
            } else {
                null
            }
        }
    } catch (e: Exception) {
        null
    }
}