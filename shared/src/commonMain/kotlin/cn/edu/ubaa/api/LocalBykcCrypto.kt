package cn.edu.ubaa.api

import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.random.Random
import kotlin.time.Clock

internal object LocalBykcCrypto {
  private const val rsaPublicKeyBase64 =
      "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDlHMQ3B5GsWnCe7Nlo1YiG/YmHdlOiKOST5aRm4iaqYSvhvWmwcigoyWTM+8bv2+sf6nQBRDWTY4KmNV7DBk1eDnTIQo6ENA31k5/tYCLEXgjPbEjCK9spiyB62fCT6cqOhbamJB0lcDJRO6Vo1m3dy+fD0jbxfDVBBNtyltIsDQIDAQAB"
  private const val keyChars = "ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678"
  private const val aesKeyLength = 16

  @OptIn(ExperimentalEncodingApi::class)
  private val rsaPublicKeyBytes by lazy { Base64.decode(rsaPublicKeyBase64) }

  fun generateAesKey(): ByteArray =
      ByteArray(aesKeyLength) { keyChars[Random.nextInt(keyChars.length)].code.toByte() }

  fun aesEncrypt(data: ByteArray, key: ByteArray): ByteArray =
      PlatformAesEcbPkcs5Padding.encrypt(data, key)

  fun aesDecrypt(data: ByteArray, key: ByteArray): ByteArray =
      PlatformAesEcbPkcs5Padding.decrypt(data, key)

  @OptIn(ExperimentalEncodingApi::class)
  fun rsaEncrypt(data: ByteArray): String =
      Base64.encode(PlatformRsaPkcs1Encrypt.encrypt(data, rsaPublicKeyBytes))

  fun sha1Sign(data: ByteArray): String =
      LocalBykcSha1.digest(data).joinToString("") { byte ->
        byte.toUByte().toString(16).padStart(2, '0')
      }

  @OptIn(ExperimentalEncodingApi::class)
  fun encryptRequest(jsonData: String): EncryptedRequest {
    val dataBytes = jsonData.encodeToByteArray()
    val aesKey = generateAesKey()
    val encryptedData = aesEncrypt(dataBytes, aesKey)
    return EncryptedRequest(
        encryptedData = Base64.encode(encryptedData),
        ak = rsaEncrypt(aesKey),
        sk = rsaEncrypt(sha1Sign(dataBytes).encodeToByteArray()),
        ts = Clock.System.now().toEpochMilliseconds().toString(),
        aesKey = aesKey,
    )
  }

  data class EncryptedRequest(
      val encryptedData: String,
      val ak: String,
      val sk: String,
      val ts: String,
      val aesKey: ByteArray,
  )
}

private object LocalBykcSha1 {
  fun digest(data: ByteArray): ByteArray {
    val bitLength = data.size.toLong() * 8L
    val paddingLength = ((56 - (data.size + 1) % 64) + 64) % 64
    val padded = ByteArray(data.size + 1 + paddingLength + 8)
    data.copyInto(padded)
    padded[data.size] = 0x80.toByte()
    for (index in 0 until 8) {
      padded[padded.lastIndex - index] = (bitLength ushr (index * 8)).toByte()
    }

    var h0 = 0x67452301
    var h1 = 0xEFCDAB89.toInt()
    var h2 = 0x98BADCFE.toInt()
    var h3 = 0x10325476
    var h4 = 0xC3D2E1F0.toInt()

    val words = IntArray(80)
    var offset = 0
    while (offset < padded.size) {
      for (index in 0 until 16) {
        val base = offset + index * 4
        words[index] =
            ((padded[base].toInt() and 0xff) shl 24) or
                ((padded[base + 1].toInt() and 0xff) shl 16) or
                ((padded[base + 2].toInt() and 0xff) shl 8) or
                (padded[base + 3].toInt() and 0xff)
      }
      for (index in 16 until 80) {
        words[index] =
            (words[index - 3] xor words[index - 8] xor words[index - 14] xor words[index - 16])
                .rotateLeft(1)
      }

      var a = h0
      var b = h1
      var c = h2
      var d = h3
      var e = h4

      for (index in 0 until 80) {
        val (f, k) =
            when (index) {
              in 0..19 -> ((b and c) or (b.inv() and d)) to 0x5A827999
              in 20..39 -> (b xor c xor d) to 0x6ED9EBA1
              in 40..59 -> ((b and c) or (b and d) or (c and d)) to 0x8F1BBCDC.toInt()
              else -> (b xor c xor d) to 0xCA62C1D6.toInt()
            }
        val temp = a.rotateLeft(5) + f + e + k + words[index]
        e = d
        d = c
        c = b.rotateLeft(30)
        b = a
        a = temp
      }

      h0 += a
      h1 += b
      h2 += c
      h3 += d
      h4 += e
      offset += 64
    }

    return ByteArray(20).also { result ->
      writeInt(result, 0, h0)
      writeInt(result, 4, h1)
      writeInt(result, 8, h2)
      writeInt(result, 12, h3)
      writeInt(result, 16, h4)
    }
  }

  private fun Int.rotateLeft(bits: Int): Int = (this shl bits) or (this ushr (32 - bits))

  private fun writeInt(target: ByteArray, offset: Int, value: Int) {
    target[offset] = (value ushr 24).toByte()
    target[offset + 1] = (value ushr 16).toByte()
    target[offset + 2] = (value ushr 8).toByte()
    target[offset + 3] = value.toByte()
  }
}
