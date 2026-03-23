package cn.edu.ubaa.cgyy

import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.spec.SecretKeySpec
import javax.imageio.ImageIO

data class CgyyCaptchaChallenge(
    val secretKey: String,
    val token: String,
    val originalImageBase64: String,
    val jigsawImageBase64: String,
)

data class CgyySolvedCaptcha(
    val moveDistance: Int,
    val pointJsonData: String,
    val pointJson: String,
    val captchaVerification: String,
)

interface CgyyCaptchaAutoSolver {
  fun solve(challenge: CgyyCaptchaChallenge): CgyySolvedCaptcha
}

class CgyyCaptchaSolver : CgyyCaptchaAutoSolver {
  override fun solve(challenge: CgyyCaptchaChallenge): CgyySolvedCaptcha {
    val background = decodeBase64Image(challenge.originalImageBase64)
    val piece = decodeBase64Image(challenge.jigsawImageBase64)
    val moveDistance = solveOffset(background, piece)
    val pointJsonData = """{"x":$moveDistance,"y":5}"""
    val pointJson = encrypt(pointJsonData, challenge.secretKey)
    val captchaVerification = encrypt("${challenge.token}---$pointJsonData", challenge.secretKey)
    return CgyySolvedCaptcha(moveDistance, pointJsonData, pointJson, captchaVerification)
  }

  internal fun solveOffset(background: BufferedImage, piece: BufferedImage): Int {
    val bgGray = toGray(background)
    val pieceGray = toGray(piece)
    val mask = buildMask(piece)
    val bounds = findBoundingBox(mask) ?: throw CgyyException("无法识别滑块图片", "captcha_error")
    val croppedPiece = crop(pieceGray, bounds)
    val croppedMask = crop(mask, bounds)
    val bgEdges = edgeDetect(bgGray)
    val pieceEdges = edgeDetect(croppedPiece)

    var bestScore = Double.NEGATIVE_INFINITY
    var bestX = 0
    val yMax = (bgEdges.size - pieceEdges.size).coerceAtLeast(0)
    val xMax = (bgEdges.first().size - pieceEdges.first().size).coerceAtLeast(0)

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
    val keyBytes = secretKey.toByteArray(Charsets.UTF_8)
    if (keyBytes.size != 16 && keyBytes.size != 24 && keyBytes.size != 32) {
      throw CgyyException("无效的验证码密钥长度: ${keyBytes.size} 字节（必须为 16/24/32 字节）", "captcha_error")
    }
    val cipher = Cipher.getInstance("AES/ECB/PKCS5Padding")
    val keySpec = SecretKeySpec(keyBytes, "AES")
    cipher.init(Cipher.ENCRYPT_MODE, keySpec)
    val encrypted = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
    return Base64.getEncoder().encodeToString(encrypted)
  }

  private fun decodeBase64Image(base64String: String): BufferedImage {
    val data =
        base64String.substringAfter("base64,", base64String).let { Base64.getDecoder().decode(it) }
    return ImageIO.read(ByteArrayInputStream(data))
        ?: throw CgyyException("验证码图片解码失败", "captcha_error")
  }

  private fun toGray(image: BufferedImage): Array<IntArray> {
    return Array(image.height) { y ->
      IntArray(image.width) { x ->
        val argb = image.getRGB(x, y)
        val r = argb shr 16 and 0xff
        val g = argb shr 8 and 0xff
        val b = argb and 0xff
        (r * 30 + g * 59 + b * 11) / 100
      }
    }
  }

  private fun buildMask(image: BufferedImage): Array<BooleanArray> {
    return Array(image.height) { y ->
      BooleanArray(image.width) { x ->
        val argb = image.getRGB(x, y)
        val alpha = argb ushr 24 and 0xff
        if (alpha > 10) return@BooleanArray true
        val r = argb shr 16 and 0xff
        val g = argb shr 8 and 0xff
        val b = argb and 0xff
        val luminance = (r * 30 + g * 59 + b * 11) / 100
        luminance < 250
      }
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
