package cn.edu.ubaa.ui.screens.splash

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** 启动界面 显示应用标题和标语 */
@Composable
fun SplashScreen(modifier: Modifier = Modifier) {
    Box(
            modifier = modifier.fillMaxSize().background(MaterialTheme.colorScheme.background),
            contentAlignment = Alignment.Center
    ) {
        Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
        ) {
            // 主标题
            Text(
                    text = "UBAA",
                    style =
                            MaterialTheme.typography.displayLarge.copy(
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 72.sp
                            ),
                    color = MaterialTheme.colorScheme.onBackground,
                    textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(16.dp))

            // 副标题
            Text(
                    text = "Make BUAA Great Again",
                    style =
                            MaterialTheme.typography.headlineMedium.copy(
                                    fontWeight = FontWeight.Medium
                            ),
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.8f),
                    textAlign = TextAlign.Center
            )
        }
    }
}
