package cn.edu.ubaa.bykc

import java.util.Base64
import kotlin.test.*

/** BykcCrypto 加密模块单元测试类 */
class BykcCryptoTest {

  @Test
  fun `generateAesKey returns 16 byte key`() {
    val key = BykcCrypto.generateAesKey()
    assertEquals(16, key.size, "AES key should be 16 bytes")
  }

  @Test
  fun `generateAesKey returns different keys each time`() {
    val key1 = BykcCrypto.generateAesKey()
    val key2 = BykcCrypto.generateAesKey()
    assertFalse(key1.contentEquals(key2), "Generated keys should be different")
  }

  @Test
  fun `aesEncrypt and aesDecrypt are reversible`() {
    val originalData = """{"pageNumber":1,"pageSize":200}""".toByteArray(Charsets.UTF_8)
    val key = BykcCrypto.generateAesKey()

    val encrypted = BykcCrypto.aesEncrypt(originalData, key)
    val decrypted = BykcCrypto.aesDecrypt(encrypted, key)

    assertContentEquals(originalData, decrypted, "Decrypted data should match original")
  }

  @Test
  fun `aesEncrypt produces different output than input`() {
    val data = "Hello, BYKC!".toByteArray(Charsets.UTF_8)
    val key = BykcCrypto.generateAesKey()

    val encrypted = BykcCrypto.aesEncrypt(data, key)

    assertFalse(data.contentEquals(encrypted), "Encrypted data should differ from original")
  }

  @Test
  fun `rsaEncrypt produces base64 encoded output`() {
    val data = "test-aes-key-123".toByteArray(Charsets.UTF_8)

    val encrypted = BykcCrypto.rsaEncrypt(data)

    // Should be valid base64 - will throw if invalid
    val decoded = Base64.getDecoder().decode(encrypted)
    assertTrue(decoded.isNotEmpty(), "Decoded RSA output should not be empty")
    // RSA 1024-bit produces 128 bytes = 172 base64 chars (with padding)
    assertTrue(encrypted.length >= 100, "RSA encrypted output should be substantial")
  }

  @Test
  fun `sha1Sign produces lowercase hex string`() {
    val data = """{"test":"data"}""".toByteArray(Charsets.UTF_8)

    val signature = BykcCrypto.sha1Sign(data)

    // SHA1 produces 20 bytes = 40 hex chars
    assertEquals(40, signature.length, "SHA1 signature should be 40 hex chars")
    assertTrue(
      signature.all { it.isDigit() || it in 'a'..'f' },
      "Signature should be lowercase hex",
    )
  }

  @Test
  fun `sha1Sign is deterministic`() {
    val data = """{"hello":"world"}""".toByteArray(Charsets.UTF_8)

    val sig1 = BykcCrypto.sha1Sign(data)
    val sig2 = BykcCrypto.sha1Sign(data)

    assertEquals(sig1, sig2, "Same data should produce same signature")
  }

  @Test
  fun `encryptRequest returns all required fields`() {
    val jsonData = """{"pageNumber":1,"pageSize":100}"""

    val request = BykcCrypto.encryptRequest(jsonData)

    // encryptedData should be base64 - will throw if invalid
    val encData = Base64.getDecoder().decode(request.encryptedData)
    assertTrue(encData.isNotEmpty(), "Encrypted data should not be empty")

    // ak (encrypted AES key) should be base64
    val akData = Base64.getDecoder().decode(request.ak)
    assertTrue(akData.isNotEmpty(), "AK should not be empty")

    // sk (encrypted signature) should be base64
    val skData = Base64.getDecoder().decode(request.sk)
    assertTrue(skData.isNotEmpty(), "SK should not be empty")

    // ts should be a timestamp (numeric string)
    assertTrue(request.ts.all { it.isDigit() }, "Timestamp should be numeric")
    assertTrue(request.ts.toLong() > 0, "Timestamp should be positive")

    // aesKey should be 16 bytes
    assertEquals(16, request.aesKey.size, "AES key should be 16 bytes")
  }

  @Test
  fun `encryptRequest can be decrypted with returned aesKey`() {
    val originalJson = """{"test":"value","number":123}"""

    val request = BykcCrypto.encryptRequest(originalJson)

    // Decrypt the encryptedData using the returned aesKey
    val encryptedBytes = Base64.getDecoder().decode(request.encryptedData)
    val decryptedBytes = BykcCrypto.aesDecrypt(encryptedBytes, request.aesKey)
    val decryptedJson = String(decryptedBytes, Charsets.UTF_8)

    assertEquals(originalJson, decryptedJson, "Decrypted data should match original")
  }

  @Test
  fun `decryptResponse correctly decrypts base64 encoded response`() {
    val originalResponse = """{"status":"0","errmsg":"请求成功","data":null}"""
    val aesKey = BykcCrypto.generateAesKey()

    // Simulate server response: encrypt then base64 encode
    val encrypted = BykcCrypto.aesEncrypt(originalResponse.toByteArray(Charsets.UTF_8), aesKey)
    val responseBase64 = Base64.getEncoder().encodeToString(encrypted)

    val decrypted = BykcCrypto.decryptResponse(responseBase64, aesKey)

    assertEquals(originalResponse, decrypted, "Decrypted response should match original")
  }

  @Test
  fun `full encryption roundtrip works correctly`() {
    // Simulate a full request-response cycle
    val requestJson = """{"courseId":12345}"""

    // Client side: encrypt request
    val encryptedRequest = BykcCrypto.encryptRequest(requestJson)

    // Server side would decrypt using the RSA-encrypted AES key
    // We simulate by using the same AES key
    val serverReceivedBytes = Base64.getDecoder().decode(encryptedRequest.encryptedData)
    val serverDecrypted = BykcCrypto.aesDecrypt(serverReceivedBytes, encryptedRequest.aesKey)
    assertEquals(requestJson, String(serverDecrypted, Charsets.UTF_8))

    // Server side: encrypt response using same AES key
    val responseJson = """{"status":"0","errmsg":"选课成功","data":{}}"""
    val serverEncrypted =
      BykcCrypto.aesEncrypt(responseJson.toByteArray(Charsets.UTF_8), encryptedRequest.aesKey)
    val serverResponseBase64 = Base64.getEncoder().encodeToString(serverEncrypted)

    // Client side: decrypt response
    val clientDecrypted = BykcCrypto.decryptResponse(serverResponseBase64, encryptedRequest.aesKey)
    assertEquals(responseJson, clientDecrypted)
  }
}
