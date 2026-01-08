package cn.edu.ubaa

import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.window.ComposeViewport
import kotlinx.browser.document
import kotlinx.coroutines.delay
import org.w3c.dom.HTMLElement

@OptIn(ExperimentalComposeUiApi::class)
fun main() {
  ComposeViewport(document.body!!) {
    App()
    LaunchedEffect(Unit) {
      val loader = document.getElementById("app-loader") as? HTMLElement
      if (loader != null) {
        loader.style.opacity = "0"
        delay(500)
        loader.remove()
      }
    }
  }
}
