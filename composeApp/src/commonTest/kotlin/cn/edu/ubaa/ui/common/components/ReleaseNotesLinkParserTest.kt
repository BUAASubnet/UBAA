package cn.edu.ubaa.ui.common.components

import kotlin.test.Test
import kotlin.test.assertEquals

class ReleaseNotesLinkParserTest {
  @Test
  fun parsesRawUrlsAsLinkSegments() {
    val segments =
        parseReleaseNotesLinks("下载 https://github.com/BUAASubnet/UBAA/releases/latest 查看详情")

    assertEquals(
        listOf(
            ReleaseNotesSegment.Text("下载 "),
            ReleaseNotesSegment.Link(
                text = "https://github.com/BUAASubnet/UBAA/releases/latest",
                url = "https://github.com/BUAASubnet/UBAA/releases/latest",
            ),
            ReleaseNotesSegment.Text(" 查看详情"),
        ),
        segments,
    )
  }

  @Test
  fun parsesMarkdownLinksWithReadableText() {
    val segments =
        parseReleaseNotesLinks("请查看 [发布页面](https://github.com/BUAASubnet/UBAA/releases)。")

    assertEquals(
        listOf(
            ReleaseNotesSegment.Text("请查看 "),
            ReleaseNotesSegment.Link(
                text = "发布页面",
                url = "https://github.com/BUAASubnet/UBAA/releases",
            ),
            ReleaseNotesSegment.Text("。"),
        ),
        segments,
    )
  }

  @Test
  fun keepsTrailingPunctuationOutsideRawUrl() {
    val segments = parseReleaseNotesLinks("修复说明：https://example.com/fix, 请更新。")

    assertEquals(
        listOf(
            ReleaseNotesSegment.Text("修复说明："),
            ReleaseNotesSegment.Link(
                text = "https://example.com/fix",
                url = "https://example.com/fix",
            ),
            ReleaseNotesSegment.Text(", 请更新。"),
        ),
        segments,
    )
  }
}
