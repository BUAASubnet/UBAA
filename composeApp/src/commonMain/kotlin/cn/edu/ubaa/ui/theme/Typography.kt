package cn.edu.ubaa.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily

@Composable expect fun getAppFontFamily(): FontFamily

@Composable expect fun PreloadFonts()

@Composable
fun getAppTypography(): Typography {
    val chineseFontFamily = getAppFontFamily()
    return Typography(
            displayLarge = TextStyle(fontFamily = chineseFontFamily),
            displayMedium = TextStyle(fontFamily = chineseFontFamily),
            displaySmall = TextStyle(fontFamily = chineseFontFamily),
            headlineLarge = TextStyle(fontFamily = chineseFontFamily),
            headlineMedium = TextStyle(fontFamily = chineseFontFamily),
            headlineSmall = TextStyle(fontFamily = chineseFontFamily),
            titleLarge = TextStyle(fontFamily = chineseFontFamily),
            titleMedium = TextStyle(fontFamily = chineseFontFamily),
            titleSmall = TextStyle(fontFamily = chineseFontFamily),
            bodyLarge = TextStyle(fontFamily = chineseFontFamily),
            bodyMedium = TextStyle(fontFamily = chineseFontFamily),
            bodySmall = TextStyle(fontFamily = chineseFontFamily),
            labelLarge = TextStyle(fontFamily = chineseFontFamily),
            labelMedium = TextStyle(fontFamily = chineseFontFamily),
            labelSmall = TextStyle(fontFamily = chineseFontFamily)
    )
}
