package cn.edu.ubaa.ui.theme

import androidx.compose.ui.graphics.Color
import kotlin.test.Test
import kotlin.test.assertTrue

class ThemeColorContrastTest {
  @Test
  fun `light primary content color stays readable for bright preset colors`() {
    val brightPresetSeeds = listOf(Color(0xFFFFEB3B), Color(0xFFFF9800), Color(0xFF2196F3))

    brightPresetSeeds.forEach { seedColor ->
      val scheme = buildLightTonalColorScheme(seedColor)

      assertTrue(
          contrastRatio(scheme.primary, scheme.onPrimary) >= 4.5f,
          "primary/onPrimary contrast was too low for $seedColor",
      )
    }
  }
}
