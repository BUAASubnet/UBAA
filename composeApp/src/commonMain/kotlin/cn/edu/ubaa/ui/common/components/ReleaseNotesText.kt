package cn.edu.ubaa.ui.common.components

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink

internal sealed interface ReleaseNotesSegment {
  data class Text(val text: String) : ReleaseNotesSegment

  data class Link(val text: String, val url: String) : ReleaseNotesSegment
}

@Composable
internal fun ReleaseNotesText(text: String, modifier: Modifier = Modifier) {
  Text(
      text = releaseNotesAnnotatedString(text, MaterialTheme.colorScheme.primary),
      modifier = modifier,
      style = MaterialTheme.typography.bodyMedium,
  )
}

internal fun parseReleaseNotesLinks(text: String): List<ReleaseNotesSegment> {
  if (text.isEmpty()) return emptyList()

  val markdownLinks =
      markdownLinkRegex.findAll(text).map { match ->
        val label = match.groupValues[1].ifBlank { match.groupValues[2] }
        LinkMatch(match.range.first, match.range.last + 1, label, match.groupValues[2])
      }
  val markdownLinkList = markdownLinks.toList()
  val rawLinks =
      rawUrlRegex.findAll(text).mapNotNull { match ->
        val start = match.range.first
        val originalEnd = match.range.last + 1
        if (markdownLinkList.any { start < it.end && originalEnd > it.start }) {
          return@mapNotNull null
        }
        val url = match.value.trimEnd { it in rawUrlTrailingPunctuation }
        if (url.isEmpty()) return@mapNotNull null
        LinkMatch(start, start + url.length, url, url)
      }

  val links = (markdownLinkList + rawLinks).sortedBy { it.start }
  if (links.isEmpty()) return listOf(ReleaseNotesSegment.Text(text))

  val segments = mutableListOf<ReleaseNotesSegment>()
  var cursor = 0
  for (link in links) {
    appendTextSegment(segments, text.substring(cursor, link.start))
    segments += ReleaseNotesSegment.Link(link.text, link.url)
    cursor = link.end
  }
  appendTextSegment(segments, text.substring(cursor))
  return segments
}

private fun releaseNotesAnnotatedString(text: String, linkColor: Color) = buildAnnotatedString {
  val linkStyle =
      TextLinkStyles(
          style = SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)
      )

  parseReleaseNotesLinks(text).forEach { segment ->
    when (segment) {
      is ReleaseNotesSegment.Text -> append(segment.text)
      is ReleaseNotesSegment.Link ->
          withLink(LinkAnnotation.Url(segment.url, styles = linkStyle)) { append(segment.text) }
    }
  }
}

private fun appendTextSegment(segments: MutableList<ReleaseNotesSegment>, text: String) {
  if (text.isNotEmpty()) segments += ReleaseNotesSegment.Text(text)
}

private data class LinkMatch(val start: Int, val end: Int, val text: String, val url: String)

private val markdownLinkRegex = Regex("""\[([^\]\n]+)]\((https?://[^)\s]+)\)""")
private val rawUrlRegex = Regex("""https?://\S+""")
private val rawUrlTrailingPunctuation =
    setOf('.', ',', ';', ':', '!', '?', ')', ']', '}', '。', '，', '；', '：', '！', '？')
