package cn.edu.ubaa.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color

private fun darkOledColorScheme(seedColor: Color) =
    darkTonalColorScheme(seedColor)
        .copy(
            background = Color.Black,
            surface = Color.Black,
            surfaceVariant = blend(seedColor, Color.Black, 0.78f),
            onBackground = Color.White,
            onSurface = Color.White,
        )

@Composable
fun UBAATheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    seedColor: Color = Color(0xFF6750A4),
    oledEnhance: Boolean = false,
    content: @Composable () -> Unit,
) {
  val colorScheme =
      when {
        darkTheme && oledEnhance -> darkOledColorScheme(seedColor)
        darkTheme -> darkTonalColorScheme(seedColor)
        else -> lightTonalColorScheme(seedColor)
      }

  MaterialTheme(colorScheme = colorScheme, typography = getAppTypography()) {
    Surface(modifier = Modifier.fillMaxSize(), color = colorScheme.background) { content() }
  }
}

private fun lightTonalColorScheme(seedColor: Color): ColorScheme {
  val primary = accessiblePrimary(seedColor, darkTheme = false)
  return lightColorScheme(
      primary = primary,
      onPrimary = Color.White,
      primaryContainer = blend(primary, Color.White, 0.80f),
      onPrimaryContainer = blend(primary, Color.Black, 0.25f),
      secondary = blend(primary, Color(0xFF006A6A), 0.35f),
      onSecondary = Color.White,
      secondaryContainer = blend(primary, Color.White, 0.86f),
      onSecondaryContainer = blend(primary, Color.Black, 0.30f),
      tertiary = blend(primary, Color(0xFF9A405D), 0.35f),
      onTertiary = Color.White,
      tertiaryContainer = blend(primary, Color.White, 0.88f),
      onTertiaryContainer = blend(primary, Color.Black, 0.28f),
      background = blend(primary, Color.White, 0.96f),
      onBackground = Color(0xFF1D1B20),
      surface = blend(primary, Color.White, 0.98f),
      onSurface = Color(0xFF1D1B20),
      surfaceVariant = blend(primary, Color.White, 0.90f),
      onSurfaceVariant = Color(0xFF49454F),
      outline = blend(primary, Color(0xFF79747E), 0.18f),
      outlineVariant = blend(primary, Color(0xFFCAC4D0), 0.35f),
  )
}

private fun darkTonalColorScheme(seedColor: Color): ColorScheme {
  val primary = accessiblePrimary(seedColor, darkTheme = true)
  return darkColorScheme(
      primary = primary,
      onPrimary = Color(0xFF1D1B20),
      primaryContainer = blend(primary, Color.Black, 0.58f),
      onPrimaryContainer = blend(primary, Color.White, 0.78f),
      secondary = blend(primary, Color(0xFF80CBC4), 0.35f),
      onSecondary = Color(0xFF1D1B20),
      secondaryContainer = blend(primary, Color.Black, 0.66f),
      onSecondaryContainer = blend(primary, Color.White, 0.82f),
      tertiary = blend(primary, Color(0xFFF48FB1), 0.35f),
      onTertiary = Color(0xFF1D1B20),
      tertiaryContainer = blend(primary, Color.Black, 0.68f),
      onTertiaryContainer = blend(primary, Color.White, 0.84f),
      background = blend(primary, Color.Black, 0.93f),
      onBackground = Color(0xFFE6E1E5),
      surface = blend(primary, Color.Black, 0.90f),
      onSurface = Color(0xFFE6E1E5),
      surfaceVariant = blend(primary, Color.Black, 0.78f),
      onSurfaceVariant = Color(0xFFCAC4D0),
      outline = blend(primary, Color(0xFF938F99), 0.22f),
      outlineVariant = blend(primary, Color(0xFF49454F), 0.35f),
  )
}

private fun accessiblePrimary(color: Color, darkTheme: Boolean): Color {
  val target = if (darkTheme) Color.White else Color.Black
  val amount = if (darkTheme) 0.32f else 0.12f
  return blend(color, target, amount)
}

private fun blend(start: Color, end: Color, amount: Float): Color {
  val clampedAmount = amount.coerceIn(0f, 1f)
  val inverseAmount = 1f - clampedAmount
  return Color(
      red = start.red * inverseAmount + end.red * clampedAmount,
      green = start.green * inverseAmount + end.green * clampedAmount,
      blue = start.blue * inverseAmount + end.blue * clampedAmount,
      alpha = start.alpha * inverseAmount + end.alpha * clampedAmount,
  )
}
