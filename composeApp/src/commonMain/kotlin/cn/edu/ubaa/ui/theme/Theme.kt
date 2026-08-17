package cn.edu.ubaa.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

private fun darkOledColorScheme(seedColor: Color) =
    buildDarkTonalColorScheme(seedColor)
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
    dynamicColor: Boolean = false,
    oledEnhance: Boolean = false,
    content: @Composable () -> Unit,
) {
  val effectiveSeedColor = if (dynamicColor) Color(0xFF6750A4) else seedColor
  val colorScheme =
      when {
        darkTheme && oledEnhance -> darkOledColorScheme(effectiveSeedColor)
        darkTheme -> buildDarkTonalColorScheme(effectiveSeedColor)
        else -> buildLightTonalColorScheme(effectiveSeedColor)
      }

  MaterialTheme(colorScheme = colorScheme, typography = getAppTypography()) {
    Surface(modifier = Modifier.fillMaxSize(), color = colorScheme.background) { content() }
  }
}

internal fun buildLightTonalColorScheme(seedColor: Color): ColorScheme {
  val primary = accessiblePrimary(seedColor, darkTheme = false)
  val primaryContainer = blend(primary, Color.White, 0.80f)
  val secondary = blend(primary, Color(0xFF006A6A), 0.35f)
  val secondaryContainer = blend(primary, Color.White, 0.86f)
  val tertiary = blend(primary, Color(0xFF9A405D), 0.35f)
  val tertiaryContainer = blend(primary, Color.White, 0.88f)
  return lightColorScheme(
      primary = primary,
      onPrimary = readableContentColorFor(primary),
      primaryContainer = primaryContainer,
      onPrimaryContainer = readableContentColorFor(primaryContainer),
      secondary = secondary,
      onSecondary = readableContentColorFor(secondary),
      secondaryContainer = secondaryContainer,
      onSecondaryContainer = readableContentColorFor(secondaryContainer),
      tertiary = tertiary,
      onTertiary = readableContentColorFor(tertiary),
      tertiaryContainer = tertiaryContainer,
      onTertiaryContainer = readableContentColorFor(tertiaryContainer),
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

private fun buildDarkTonalColorScheme(seedColor: Color): ColorScheme {
  val primary = accessiblePrimary(seedColor, darkTheme = true)
  val primaryContainer = blend(primary, Color.Black, 0.58f)
  val secondary = blend(primary, Color(0xFF80CBC4), 0.35f)
  val secondaryContainer = blend(primary, Color.Black, 0.66f)
  val tertiary = blend(primary, Color(0xFFF48FB1), 0.35f)
  val tertiaryContainer = blend(primary, Color.Black, 0.68f)
  return darkColorScheme(
      primary = primary,
      onPrimary = readableContentColorFor(primary),
      primaryContainer = primaryContainer,
      onPrimaryContainer = readableContentColorFor(primaryContainer),
      secondary = secondary,
      onSecondary = readableContentColorFor(secondary),
      secondaryContainer = secondaryContainer,
      onSecondaryContainer = readableContentColorFor(secondaryContainer),
      tertiary = tertiary,
      onTertiary = readableContentColorFor(tertiary),
      tertiaryContainer = tertiaryContainer,
      onTertiaryContainer = readableContentColorFor(tertiaryContainer),
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

internal fun contrastRatio(background: Color, foreground: Color): Float {
  val backgroundLuminance = relativeLuminance(background)
  val foregroundLuminance = relativeLuminance(foreground)
  val lighter = max(backgroundLuminance, foregroundLuminance)
  val darker = min(backgroundLuminance, foregroundLuminance)
  return (lighter + 0.05f) / (darker + 0.05f)
}

private fun accessiblePrimary(color: Color, darkTheme: Boolean): Color {
  val target = if (darkTheme) Color.White else Color.Black
  val amount = if (darkTheme) 0.32f else 0.12f
  return blend(color, target, amount)
}

private fun readableContentColorFor(background: Color): Color {
  val whiteContrast = contrastRatio(background, Color.White)
  val blackContrast = contrastRatio(background, Color.Black)
  return if (whiteContrast >= blackContrast) Color.White else Color.Black
}

private fun relativeLuminance(color: Color): Float =
    0.2126f * linearize(color.red) +
        0.7152f * linearize(color.green) +
        0.0722f * linearize(color.blue)

private fun linearize(component: Float): Float =
    if (component <= 0.03928f) {
      component / 12.92f
    } else {
      ((component + 0.055f) / 1.055f).toDouble().pow(2.4).toFloat()
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
