package cn.edu.ubaa.ui.screens.ihome

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toAwtImage
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import cn.edu.ubaa.api.feature.IhomeApi
import cn.edu.ubaa.model.dto.*
import java.io.File
import javax.imageio.ImageIO
import kotlin.test.assertEquals
import org.junit.Rule
import org.junit.Test

class IhomeScreenTest {
  @get:Rule val compose = createComposeRule()

  @Test fun `窄屏可搜索并打开详情`() = checkScreen(390, 720, "phone")

  @Test fun `宽屏可搜索并打开详情`() = checkScreen(1024, 720, "desktop")

  private fun checkScreen(width: Int, height: Int, name: String) {
    val item =
        IhomeAppeal(
            id = 42,
            content = "建议延长图书馆周末开放时间，方便同学们安排自习。",
            status = "已发布",
            category = "我要建议",
            publishedAt = "2026-09-17",
            departments = listOf("图书馆"),
            isFollowed = false,
            isSupported = false,
            followCount = 2,
            supportCount = 8,
            replies = listOf(IhomeReply("已收到建议，正在评估开放安排。", "图书馆", "2026-09-17")),
            history = listOf(IhomeHistory("学生中心已分办", "2026-09-17")),
        )
    var keyword = ""
    val api =
        object : IhomeApi() {
          override suspend fun getConfig() =
              Result.success(IhomeConfig(true, categories = listOf(IhomeCategory(4, "我要建议"))))

          override suspend fun getPage(query: IhomeQuery): Result<IhomePage> {
            keyword = query.keyword
            return Result.success(IhomePage(listOf(IhomeEntry(item)), 1, 1, 1))
          }

          override suspend fun getDetail(id: Long, mine: Boolean) = Result.success(item)
        }
    val vm = IhomeViewModel(api)
    compose.setContent {
      MaterialTheme {
        Box(Modifier.size(width.dp, height.dp).testTag("ihome-preview")) { IhomeScreen(vm) }
      }
    }
    compose.waitUntil(5000) { vm.uiState.value.entries.isNotEmpty() }
    compose.onNodeWithText(item.content).assertIsDisplayed()
    val directory = File(System.getProperty("java.io.tmpdir"), "ubaa-ihome-ui").apply { mkdirs() }
    ImageIO.write(
        compose.onNodeWithTag("ihome-preview").captureToImage().toAwtImage(),
        "png",
        File(directory, "$name.png"),
    )
    compose.onNodeWithText("搜索诉求与回复").performTextInput("图书馆")
    compose.onNodeWithContentDescription("搜索").performClick()
    compose.waitForIdle()
    assertEquals("图书馆", keyword)
    compose.onNodeWithText(item.content).performClick()
    compose.waitUntil(5000) { vm.uiState.value.detail != null }
    compose.onNodeWithText("诉求详情").assertIsDisplayed()
    compose.onNodeWithContentDescription("关闭详情").performClick()
    compose.onNodeWithText("诉求详情").assertDoesNotExist()
  }
}
