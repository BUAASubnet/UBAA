package cn.edu.ubaa.api

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class LocalCgyySignerTest {
  private val signer = LocalCgyySigner()

  @Test
  fun `sign ignores empty values and removed keys`() {
    val timestamp = 1710000000000L
    val signWithNoise =
        signer.sign(
            "/api/test",
            mapOf(
                "b" to "2",
                "a" to "1",
                "empty" to "",
                "none" to null,
                "id" to 123,
            ),
            timestamp,
        )
    val cleanSign = signer.sign("/api/test", mapOf("a" to "1", "b" to "2"), timestamp)

    assertEquals(cleanSign, signWithNoise)
  }

  @Test
  fun `addNoCacheIfMissing only adds once`() {
    val first = signer.addNoCacheIfMissing(mapOf("page" to 0), 123L)
    val second = signer.addNoCacheIfMissing(first, 456L)

    assertEquals(123L, first["nocache"])
    assertEquals(123L, second["nocache"])
    assertFalse("id" in signer.cleanParams(mapOf("id" to 1, "page" to 0)))
  }
}
