package cn.edu.ubaa.ui

import cn.edu.ubaa.ui.screens.menu.advancedFeatureItems
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class AdvancedFeaturesScreenTest {
  @Test
  fun `高级功能包含唯一的iHome入口`() {
    assertEquals(1, advancedFeatureItems().count { it.id == "ihome" })
  }

  @Test
  fun `advanced features do not include signin entry`() {
    assertFalse(advancedFeatureItems().any { it.id == "signin" })
  }
}
