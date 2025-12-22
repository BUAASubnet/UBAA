package cn.edu.ubaa.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo

// 个人信息界面
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun UserInfoScreen(
        userData: UserData,
        userInfo: UserInfo?,
        onLogoutClick: () -> Unit,
        modifier: Modifier = Modifier
) {
    Column(modifier = modifier.fillMaxSize().padding(16.dp)) {
        TopAppBar(
                title = { Text("个人信息") },
                actions = { TextButton(onClick = onLogoutClick) { Text("退出登录") } }
        )

        Spacer(modifier = Modifier.height(16.dp))

        Card(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text(
                        text = "基本信息",
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(bottom = 16.dp)
                )

                UserInfoRow("姓名", userData.name)
                UserInfoRow("学号", userData.schoolid)

                userInfo?.let { info ->
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                            text = "详细信息",
                            style = MaterialTheme.typography.titleMedium,
                            modifier = Modifier.padding(bottom = 16.dp)
                    )

                    info.username?.let { UserInfoRow("用户名", it) }
                    info.email?.let { UserInfoRow("邮箱", it) }
                    info.phone?.let { UserInfoRow("手机", it) }
                    info.idCardTypeName?.let { UserInfoRow("证件类型", it) }
                    info.idCardNumber?.let { UserInfoRow("证件号码", maskIdCard(it)) }
                }
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        OutlinedButton(onClick = onLogoutClick, modifier = Modifier.fillMaxWidth().height(48.dp)) {
            Text("退出登录")
        }
    }
}

@Composable
private fun UserInfoRow(label: String, value: String, modifier: Modifier = Modifier) {
    Row(
            modifier = modifier.fillMaxWidth().padding(vertical = 4.dp),
            horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(text = value, style = MaterialTheme.typography.bodyMedium)
    }
}

private fun maskIdCard(idCard: String): String {
    return if (idCard.length >= 8) {
        idCard.substring(0, 4) + "****" + idCard.substring(idCard.length - 4)
    } else {
        idCard
    }
}
