package cn.edu.ubaa.demo

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import cn.edu.ubaa.ui.LoginScreen
import cn.edu.ubaa.ui.LoginFormState
import cn.edu.ubaa.ui.UserInfoScreen

/**
 * Demo screens to showcase the UI implementation
 */
@Composable
fun LoginScreenDemo() {
    MaterialTheme {
        LoginScreen(
            loginFormState = LoginFormState("student123", ""),
            onUsernameChange = {},
            onPasswordChange = {},
            onLoginClick = {},
            isLoading = false,
            error = null,
            modifier = Modifier
                .background(MaterialTheme.colorScheme.background)
                .fillMaxSize()
        )
    }
}

@Composable
fun LoginScreenWithErrorDemo() {
    MaterialTheme {
        LoginScreen(
            loginFormState = LoginFormState("student123", "wrongpass"),
            onUsernameChange = {},
            onPasswordChange = {},
            onLoginClick = {},
            isLoading = false,
            error = "学号或密码错误",
            modifier = Modifier
                .background(MaterialTheme.colorScheme.background)
                .fillMaxSize()
        )
    }
}

@Composable
fun UserInfoScreenDemo() {
    MaterialTheme {
        val userData = UserData(name = "李沐衡", schoolid = "24182104")
        val userInfo = UserInfo(
            idCardType = "1",
            idCardTypeName = "居民身份证",
            phone = "132******79",
            schoolid = "24182104",
            name = "李沐衡",
            idCardNumber = "11**************18",
            email = "t****h@outlook.com",
            username = "24182104"
        )
        
        UserInfoScreen(
            userData = userData,
            userInfo = userInfo,
            onLogoutClick = {},
            modifier = Modifier
                .background(MaterialTheme.colorScheme.background)
                .fillMaxSize()
        )
    }
}