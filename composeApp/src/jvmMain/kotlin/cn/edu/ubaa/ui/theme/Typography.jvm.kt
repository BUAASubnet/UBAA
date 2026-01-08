package cn.edu.ubaa.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontFamily

@Composable actual fun getAppFontFamily(): FontFamily = FontFamily.Default

@Composable
actual fun PreloadFonts() {
  // JVM 不需要预加载自定义字体
}
