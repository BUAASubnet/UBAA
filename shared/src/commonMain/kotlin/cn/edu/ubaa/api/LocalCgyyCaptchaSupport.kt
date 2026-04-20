package cn.edu.ubaa.api

import io.ktor.http.HttpStatusCode
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

internal data class LocalCgyyCaptchaChallenge(
    val secretKey: String,
    val token: String,
    val originalImageBase64: String,
    val jigsawImageBase64: String,
)

internal data class LocalCgyySolvedCaptcha(
    val moveDistance: Int,
    val pointJsonData: String,
    val pointJson: String,
    val captchaVerification: String,
)

internal interface LocalCgyyCaptchaSolver {
  fun solve(challenge: LocalCgyyCaptchaChallenge): LocalCgyySolvedCaptcha
}

internal class DefaultLocalCgyyCaptchaSolver : LocalCgyyCaptchaSolver {
  @OptIn(ExperimentalEncodingApi::class)
  override fun solve(challenge: LocalCgyyCaptchaChallenge): LocalCgyySolvedCaptcha {
    val background =
        PlatformImageRasterDecoder.decode(
            Base64.decode(
                challenge.originalImageBase64.substringAfter(
                    "base64,",
                    challenge.originalImageBase64,
                )
            )
        )
    val piece =
        PlatformImageRasterDecoder.decode(
            Base64.decode(
                challenge.jigsawImageBase64.substringAfter("base64,", challenge.jigsawImageBase64)
            )
        )
    val moveDistance = solveOffset(background, piece)
    val pointJsonData = """{"x":$moveDistance,"y":5}"""
    val pointJson = encrypt(pointJsonData, challenge.secretKey)
    val captchaVerification = encrypt("${challenge.token}---$pointJsonData", challenge.secretKey)
    return LocalCgyySolvedCaptcha(moveDistance, pointJsonData, pointJson, captchaVerification)
  }

  internal fun solveOffset(background: LocalCgyyImageData, piece: LocalCgyyImageData): Int {
    val bgGray = toGray(background)
    val pieceGray = toGray(piece)
    val mask = buildMask(piece)
    val bounds =
        findBoundingBox(mask)
            ?: throw LocalCgyyApiException(
                "验证码图片缺少有效掩码",
                "captcha_error",
                HttpStatusCode.BadGateway,
            )
    val croppedPiece = crop(pieceGray, bounds)
    val croppedMask = crop(mask, bounds)
    val bgEdges = edgeDetect(bgGray)
    val pieceEdges = edgeDetect(croppedPiece)

    var bestScore = Double.NEGATIVE_INFINITY
    var bestX = 0
    val yMax = (bgEdges.size - pieceEdges.size).coerceAtLeast(0)
    val xMax =
        ((bgEdges.firstOrNull()?.size ?: 0) - (pieceEdges.firstOrNull()?.size ?: 0)).coerceAtLeast(
            0
        )

    for (y in 0..yMax) {
      for (x in 0..xMax) {
        var score = 0.0
        var edgePixels = 0
        var maskPixels = 0
        for (py in pieceEdges.indices) {
          for (px in pieceEdges[py].indices) {
            if (!croppedMask[py][px]) continue
            maskPixels++
            val bgValue = bgEdges[y + py][x + px]
            val pieceValue = pieceEdges[py][px]
            if (pieceValue > 0) {
              edgePixels++
              score += if (bgValue > 0) 3.0 else -1.5
            } else if (bgValue == 0) {
              score += 0.15
            }
          }
        }
        if (maskPixels == 0 || edgePixels == 0) continue
        score /= edgePixels.toDouble()
        score += maskPixels * 0.0001
        if (score > bestScore) {
          bestScore = score
          bestX = x
        }
      }
    }
    return bestX
  }

  internal fun encrypt(plainText: String, secretKey: String): String {
    val keyBytes = secretKey.encodeToByteArray()
    require(keyBytes.size == 16 || keyBytes.size == 24 || keyBytes.size == 32) {
      "Invalid AES key size: ${keyBytes.size}"
    }
    val encrypted = PlatformAesEcbPkcs5Padding.encrypt(plainText.encodeToByteArray(), keyBytes)
    return Base64.encode(encrypted)
  }

  private fun toGray(image: LocalCgyyImageData): Array<IntArray> =
      Array(image.height) { y ->
        IntArray(image.width) { x ->
          val argb = image.argb[y * image.width + x]
          val r = argb shr 16 and 0xff
          val g = argb shr 8 and 0xff
          val b = argb and 0xff
          (r * 30 + g * 59 + b * 11) / 100
        }
      }

  private fun buildMask(image: LocalCgyyImageData): Array<BooleanArray> =
      Array(image.height) { y ->
        BooleanArray(image.width) { x ->
          val argb = image.argb[y * image.width + x]
          val alpha = argb ushr 24 and 0xff
          if (alpha > 10) return@BooleanArray true
          val r = argb shr 16 and 0xff
          val g = argb shr 8 and 0xff
          val b = argb and 0xff
          val luminance = (r * 30 + g * 59 + b * 11) / 100
          luminance < 250
        }
      }

  private fun edgeDetect(gray: Array<IntArray>): Array<IntArray> {
    val height = gray.size
    val width = gray.firstOrNull()?.size ?: 0
    return Array(height) { y ->
      IntArray(width) { x ->
        val center = gray[y][x]
        val right = gray[y][(x + 1).coerceAtMost(width - 1)]
        val down = gray[(y + 1).coerceAtMost(height - 1)][x]
        val edge = kotlin.math.abs(center - right) + kotlin.math.abs(center - down)
        if (edge > 35) 255 else 0
      }
    }
  }

  private fun findBoundingBox(mask: Array<BooleanArray>): IntArray? {
    var minX = Int.MAX_VALUE
    var minY = Int.MAX_VALUE
    var maxX = Int.MIN_VALUE
    var maxY = Int.MIN_VALUE
    for (y in mask.indices) {
      for (x in mask[y].indices) {
        if (!mask[y][x]) continue
        minX = minOf(minX, x)
        minY = minOf(minY, y)
        maxX = maxOf(maxX, x)
        maxY = maxOf(maxY, y)
      }
    }
    if (minX == Int.MAX_VALUE) return null
    return intArrayOf(minX, minY, maxX, maxY)
  }

  private fun crop(source: Array<IntArray>, bounds: IntArray): Array<IntArray> {
    val width = bounds[2] - bounds[0] + 1
    val height = bounds[3] - bounds[1] + 1
    return Array(height) { y -> IntArray(width) { x -> source[bounds[1] + y][bounds[0] + x] } }
  }

  private fun crop(source: Array<BooleanArray>, bounds: IntArray): Array<BooleanArray> {
    val width = bounds[2] - bounds[0] + 1
    val height = bounds[3] - bounds[1] + 1
    return Array(height) { y -> BooleanArray(width) { x -> source[bounds[1] + y][bounds[0] + x] } }
  }
}
