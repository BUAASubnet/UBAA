package cn.edu.ubaa

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp

@Composable
fun SplashScreen(modifier: Modifier = Modifier) {
    Column(
            modifier = modifier.background(MaterialTheme.colorScheme.background),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
                text = "UBAA",
                style =
                        MaterialTheme.typography.displayLarge.copy(
                                fontWeight = FontWeight.Bold,
                                fontSize = 48.sp
                        ),
                color = MaterialTheme.colorScheme.onBackground,
                textAlign = TextAlign.Center
        )
        Text(
                text = "Make BUAA Great Again",
                style =
                        MaterialTheme.typography.headlineMedium.copy(
                                fontWeight = FontWeight.Medium,
                                fontSize = 20.sp
                        ),
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.8f),
                textAlign = TextAlign.Center
        )
    }
}
