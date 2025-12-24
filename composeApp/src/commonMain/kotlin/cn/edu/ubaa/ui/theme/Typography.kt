package cn.edu.ubaa.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily

@Composable expect fun getAppFontFamily(): FontFamily

@Composable expect fun PreloadFonts()

@Composable
fun getAppTypography(): Typography {
    val chineseFontFamily = getAppFontFamily()
    val defaultTypography = Typography()
    return Typography(
            displayLarge = defaultTypography.displayLarge.copy(fontFamily = chineseFontFamily),
            displayMedium = defaultTypography.displayMedium.copy(fontFamily = chineseFontFamily),
            displaySmall = defaultTypography.displaySmall.copy(fontFamily = chineseFontFamily),
            headlineLarge = defaultTypography.headlineLarge.copy(fontFamily = chineseFontFamily),
            headlineMedium = defaultTypography.headlineMedium.copy(fontFamily = chineseFontFamily),
            headlineSmall = defaultTypography.headlineSmall.copy(fontFamily = chineseFontFamily),
            titleLarge = defaultTypography.titleLarge.copy(fontFamily = chineseFontFamily),
            titleMedium = defaultTypography.titleMedium.copy(fontFamily = chineseFontFamily),
            titleSmall = defaultTypography.titleSmall.copy(fontFamily = chineseFontFamily),
            bodyLarge = defaultTypography.bodyLarge.copy(fontFamily = chineseFontFamily),
            bodyMedium = defaultTypography.bodyMedium.copy(fontFamily = chineseFontFamily),
            bodySmall = defaultTypography.bodySmall.copy(fontFamily = chineseFontFamily),
            labelLarge = defaultTypography.labelLarge.copy(fontFamily = chineseFontFamily),
            labelMedium = defaultTypography.labelMedium.copy(fontFamily = chineseFontFamily),
            labelSmall = defaultTypography.labelSmall.copy(fontFamily = chineseFontFamily)
    )
}
