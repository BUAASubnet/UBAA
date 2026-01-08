package cn.edu.ubaa.ui.screens.menu

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AssignmentTurnedIn
import androidx.compose.material.icons.filled.HowToReg
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.UserInfo

@Composable
fun AdvancedFeaturesScreen(
        onSigninClick: () -> Unit,
        onEvaluationClick: () -> Unit,
        modifier: Modifier = Modifier
) {
        val features =
                listOf(
                        FeatureItem(
                                id = "signin",
                                title = "课程签到",
                                description = "快速完成课堂签到",
                                icon = Icons.Default.HowToReg
                        ),
                        FeatureItem(
                                id = "evaluation",
                                title = "自动评教",
                                description = "一键完成学期末评教任务",
                                icon = Icons.Default.AssignmentTurnedIn
                        ),
                        FeatureItem(
                                id = "more",
                                title = "更多功能",
                                description = "更多高级功能正在开发中...",
                                icon = Icons.Default.MoreHoriz
                        )
                )

        Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
                // Text(
                //         text = "高级功能",
                //         style = MaterialTheme.typography.headlineMedium,
                //         fontWeight = FontWeight.Bold,
                //         modifier = Modifier.padding(bottom = 16.dp)
                // )

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
                                                        "signin" -> onSigninClick()
                                                        "evaluation" -> onEvaluationClick()
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
                        modifier = Modifier.padding(16.dp).fillMaxSize(),
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

@Composable
fun MyScreen(userInfo: UserInfo?, modifier: Modifier = Modifier) {
        Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
                // Text(
                //         text = "我的",
                //         style = MaterialTheme.typography.headlineMedium,
                //         fontWeight = FontWeight.Bold,
                //         modifier = Modifier.padding(bottom = 16.dp)
                // )

                Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors =
                                CardDefaults.cardColors(
                                        containerColor = MaterialTheme.colorScheme.surfaceVariant
                                )
                ) {
                        Column(
                                modifier = Modifier.fillMaxWidth().padding(16.dp),
                                horizontalAlignment = Alignment.Start
                        ) {
                                if (userInfo != null) {
                                        UserInfoItem("姓名", userInfo.name ?: "未知")
                                        UserInfoItem("学号", userInfo.schoolid ?: "未知")
                                        UserInfoItem("用户名", userInfo.username ?: "未知")
                                        UserInfoItem("手机号", userInfo.phone ?: "未绑定")
                                        UserInfoItem("邮箱", userInfo.email ?: "未绑定")
                                        UserInfoItem("证件类型", userInfo.idCardTypeName ?: "未知")
                                        UserInfoItem("证件号码", userInfo.idCardNumber ?: "未知")
                                } else {
                                        Text(
                                                text = "正在加载用户信息...",
                                                style = MaterialTheme.typography.bodyMedium,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                modifier = Modifier.padding(16.dp)
                                        )
                                }
                        }
                }
        }
}

@Composable
private fun UserInfoItem(label: String, value: String) {
        Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween
        ) {
                Text(
                        text = label,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                        text = value,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                )
        }
}

@Composable
fun AboutScreen(modifier: Modifier = Modifier) {
        Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
                // Text(
                //         text = "关于",
                //         style = MaterialTheme.typography.headlineMedium,
                //         fontWeight = FontWeight.Bold,
                //         modifier = Modifier.padding(bottom = 16.dp)
                // )

                Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(16.dp)) {
                                Text(
                                        text = "UBAA 应用",
                                        style = MaterialTheme.typography.titleLarge,
                                        fontWeight = FontWeight.Bold
                                )

                                Spacer(modifier = Modifier.height(8.dp))

                                Text(
                                        text = "版本：1.0.0",
                                        style = MaterialTheme.typography.bodyMedium,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                )

                                Spacer(modifier = Modifier.height(16.dp))

                                Text(
                                        text = "UBAA 是一个用于（部分）代替i北航功能的程序。",
                                        style = MaterialTheme.typography.bodyMedium
                                )

                                Spacer(modifier = Modifier.height(8.dp))

                                Text(
                                        text = "主要功能：",
                                        style = MaterialTheme.typography.bodyMedium,
                                        fontWeight = FontWeight.Medium
                                )

                                Spacer(modifier = Modifier.height(4.dp))

                                Text(
                                        text =
                                                "• 课程表查询\n• 今日课程提醒\n• 个人信息管理\n• 博雅课程\n• 考试查询\n• 更多功能持续开发中...",
                                        style = MaterialTheme.typography.bodyMedium
                                )

                                Spacer(modifier = Modifier.height(16.dp))

                                Text(
                                        text = "技术栈：Kotlin Multiplatform + Compose Multiplatform",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                )

                                Spacer(modifier = Modifier.height(24.dp))

                                val uriHandler = LocalUriHandler.current

                                Text(
                                        text = "开源项目 (GitHub)",
                                        style = MaterialTheme.typography.titleMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                        modifier =
                                                Modifier.clickable {
                                                        uriHandler.openUri(
                                                                "https://github.com/BUAASubnet/UBAA"
                                                        )
                                                }
                                )

                                Spacer(modifier = Modifier.height(12.dp))

                                Text(
                                        text = "反馈建议 (Issues)",
                                        style = MaterialTheme.typography.titleMedium,
                                        color = MaterialTheme.colorScheme.primary,
                                        modifier =
                                                Modifier.clickable {
                                                        uriHandler.openUri(
                                                                "https://github.com/BUAASubnet/UBAA/issues"
                                                        )
                                                }
                                )
                        }
                }
        }
}
