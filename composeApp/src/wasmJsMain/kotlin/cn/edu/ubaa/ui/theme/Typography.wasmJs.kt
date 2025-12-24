package cn.edu.ubaa.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.text.font.FontFamily
import org.jetbrains.compose.resources.Font
import ubaa.composeapp.generated.resources.Res
import ubaa.composeapp.generated.resources.yahei

@Composable
actual fun getAppFontFamily(): FontFamily {
    val font = Font(Res.font.yahei)
    return remember(font) { FontFamily(font) }
}

@Composable
actual fun PreloadFonts() {
    val fontFamilyResolver = LocalFontFamilyResolver.current
    val font = Font(Res.font.yahei)
    LaunchedEffect(font) {
        try {
            fontFamilyResolver.preload(FontFamily(font))
        } catch (e: Exception) {
            println("Font preload failed: ${e.message}")
        }
    }
}
