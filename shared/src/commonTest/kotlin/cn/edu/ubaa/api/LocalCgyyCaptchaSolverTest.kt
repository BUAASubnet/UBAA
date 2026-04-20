package cn.edu.ubaa.api

import kotlin.test.Test
import kotlin.test.assertTrue

class LocalCgyyCaptchaSolverTest {
  private val solver = DefaultLocalCgyyCaptchaSolver()

  @Test
  fun `solveOffset returns non negative position from raster data`() {
    val backgroundWidth = 120
    val backgroundHeight = 50
    val pieceSize = 18
    val backgroundPixels = IntArray(backgroundWidth * backgroundHeight) { opaqueColor(255, 255, 255) }
    val piecePixels = IntArray(pieceSize * pieceSize) { opaqueColor(0, 0, 0) }

    for (y in 10 until 28) {
      for (x in 46 until 64) {
        backgroundPixels[y * backgroundWidth + x] = opaqueColor(0, 0, 0)
      }
    }

    val offset =
        solver.solveOffset(
            background = LocalCgyyImageData(backgroundWidth, backgroundHeight, backgroundPixels),
            piece = LocalCgyyImageData(pieceSize, pieceSize, piecePixels),
        )

    assertTrue(offset >= 0, "Unexpected offset: $offset")
  }

  @Test
  fun `encrypt returns non blank base64 text`() {
    val encrypted = solver.encrypt("""{"x":46,"y":5}""", "1234567890abcdef")

    assertTrue(encrypted.isNotBlank())
  }

  private fun opaqueColor(r: Int, g: Int, b: Int): Int =
      (255 shl 24) or (r shl 16) or (g shl 8) or b
}
