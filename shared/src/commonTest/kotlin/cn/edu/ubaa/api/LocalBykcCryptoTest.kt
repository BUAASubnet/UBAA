package cn.edu.ubaa.api

import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LocalBykcCryptoTest {
  @Test
  fun `sha1Sign matches known digest`() {
    val digest = LocalBykcCrypto.sha1Sign("abc".encodeToByteArray())

    assertEquals("a9993e364706816aba3e25717850c26c9cd0d89d", digest)
  }

  @OptIn(ExperimentalEncodingApi::class)
  @Test
  fun `encryptRequest returns decryptable payload and rsa headers`() {
    val originalJson = """{"pageNumber":1,"pageSize":20}"""

    val request = LocalBykcCrypto.encryptRequest(originalJson)

    assertTrue(request.ak.isNotBlank())
    assertTrue(request.sk.isNotBlank())
    assertTrue(request.ts.all { it.isDigit() })
    assertEquals(16, request.aesKey.size)

    val encryptedBody = Base64.decode(request.encryptedData)
    val decryptedBody = LocalBykcCrypto.aesDecrypt(encryptedBody, request.aesKey).decodeToString()

    assertEquals(originalJson, decryptedBody)
    assertEquals(128, Base64.decode(request.ak).size)
    assertEquals(128, Base64.decode(request.sk).size)
  }
}
