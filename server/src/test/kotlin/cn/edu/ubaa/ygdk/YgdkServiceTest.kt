package cn.edu.ubaa.ygdk

import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import java.io.ByteArrayInputStream
import java.time.Duration
import java.time.LocalDate
import java.time.LocalDateTime
import javax.imageio.ImageIO
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class YgdkServiceTest {
  @Test
  fun `getOverview prefers sports classify and running item`() = runBlocking {
    val client =
        FakeYgdkClient(
            classifies =
                listOf(
                    YgdkClassifyRaw(classifyId = 1, name = "活动专区", termNum = 12),
                    YgdkClassifyRaw(classifyId = 9, name = "体育锻炼", termNum = 16),
                ),
            itemsByClassify =
                mapOf(
                    9 to
                        listOf(
                            YgdkItemRaw(itemId = 2, name = "健走", sort = 2),
                            YgdkItemRaw(itemId = 7, name = "跑步", sort = 1),
                        )
                ),
            count = YgdkCountRaw(termCountShow = 5, termNum = 18),
            term = YgdkTermRaw(termId = 20261, name = "2026春"),
        )

    val service = YgdkService(clientProvider = { client })
    val overview = service.getOverview("2418")

    assertEquals(9, overview.classifyId)
    assertEquals("体育锻炼", overview.classifyName)
    assertEquals(7, overview.defaultItemId)
    assertEquals("跑步", overview.defaultItemName)
    assertEquals(5, overview.summary.termCount)
    assertEquals(18, overview.summary.termTarget)
    assertEquals(2, overview.items.size)
  }

  @Test
  fun `getOverview retries with fresh client after auth failure`() = runBlocking {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)
    val firstClient = ExpiringYgdkClient()
    val secondClient = FakeYgdkClient()
    var creations = 0
    val service =
        YgdkService(
            clientProvider = {
              creations++
              if (creations == 1) firstClient else secondClient
            }
        )

    try {
      val overview = service.getOverview("2418")

      assertEquals(2, creations)
      assertTrue(firstClient.closed)
      assertEquals(1, overview.defaultItemId)
      assertEquals("跑步", overview.defaultItemName)
      assertContains(
          registry.scrape(),
          "ubaa_retry_events_total{feature=\"ygdk\",operation=\"get_overview\",reason=\"client_refresh\"}",
      )
    } finally {
      AppObservability.reset(registry)
      registry.close()
    }
  }

  @Test
  fun `getRecords reuses resolved context from recent overview`() = runBlocking {
    val client =
        object : FakeYgdkClient() {
          var classifyCalls = 0
          var itemCalls = 0
          var countCalls = 0
          var termCalls = 0

          override suspend fun getClassifyList(): List<YgdkClassifyRaw> {
            classifyCalls++
            return super.getClassifyList()
          }

          override suspend fun getItemList(classifyId: Int): List<YgdkItemRaw> {
            itemCalls++
            return super.getItemList(classifyId)
          }

          override suspend fun getCheckCount(classifyId: Int): YgdkCountRaw {
            countCalls++
            return super.getCheckCount(classifyId)
          }

          override suspend fun getTerm(): YgdkTermRaw {
            termCalls++
            return super.getTerm()
          }
        }
    val service = YgdkService(clientProvider = { client })

    service.getOverview("2418")
    service.getRecords("2418", page = 1, size = 20)

    assertEquals(1, client.classifyCalls)
    assertEquals(1, client.itemCalls)
    assertEquals(1, client.countCalls)
    assertEquals(1, client.termCalls)
  }

  @Test
  fun `cleanupExpiredClients removes expired contexts and orphaned mutexes`() {
    val service = YgdkService(clientProvider = { FakeYgdkClient() })
    val now = System.currentTimeMillis()

    service.cacheContextForTesting("expired", now - 1)
    service.cacheContextForTesting("active", now + 60_000)
    service.cacheClientForTesting(
        username = "active",
        client = FakeYgdkClient(),
        lastAccessAt = now,
    )

    val removed = service.cleanupExpiredClients()

    assertEquals(0, removed)
    assertFalse(service.hasCachedContextForTesting("expired"))
    assertFalse(service.hasContextMutexForTesting("expired"))
    assertTrue(service.hasCachedContextForTesting("active"))
    assertTrue(service.hasContextMutexForTesting("active"))
  }

  @Test
  fun `image generator creates fully transparent png`() {
    val generated = YgdkImageGenerator(fileNameProvider = { "transparent.png" }).generate()
    val image = ImageIO.read(ByteArrayInputStream(generated.bytes))

    assertEquals("transparent.png", generated.fileName)
    assertEquals("image/png", generated.mimeType)
    assertNotNull(image)
    assertEquals(0, image.getRGB(0, 0) ushr 24)
    assertEquals(0, image.getRGB(image.width / 2, image.height / 2) ushr 24)
    assertEquals(0, image.getRGB(image.width - 1, image.height - 1) ushr 24)
  }

  @Test
  fun `submitClockin fills defaults and uploads generated image`() = runBlocking {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)
    val generatedImage =
        YgdkGeneratedImage(
            bytes = byteArrayOf(9, 8, 7, 6),
            fileName = "auto-proof.png",
            mimeType = "image/png",
        )
    val client =
        FakeYgdkClient(
            count = YgdkCountRaw(termCountShow = 4, termNum = 16),
            clockinResult = YgdkClockinResultRaw(recordId = 1001, termCountShow = 5, termNum = 16),
        )
    val service =
        YgdkService(
            clientProvider = { client },
            nowProvider = { LocalDateTime.parse("2026-04-01T15:30:00") },
            random = Random(0),
            imageGenerator =
                object : YgdkImageGenerator() {
                  override fun generate(): YgdkGeneratedImage = generatedImage
                },
        )

    try {
      val result = service.submitClockin("2418", YgdkClockinSubmitRequest())

      assertTrue(result.success)
      assertEquals("打卡成功", result.message)
      assertEquals(1001, result.recordId)
      assertEquals("操场", client.lastClockinPlace)
      assertFalse(client.lastClockinOpen)
      assertEquals(1, client.lastClockinItemId)
      assertEquals("跑步", client.lastClockinItemName)
      val startAt = assertNotNull(client.lastClockinStartAt)
      val endAt = assertNotNull(client.lastClockinEndAt)
      val today = LocalDate.parse("2026-04-01")
      assertEquals(1L, Duration.between(startAt, endAt).toHours())
      assertEquals(startAt.toLocalDate(), endAt.toLocalDate())
      assertTrue(startAt.toLocalDate() in LocalDate.parse("2026-03-30")..today)
      assertTrue(startAt.hour in 8..21)
      assertEquals(0, startAt.minute)
      if (startAt.toLocalDate() == today) {
        assertTrue(endAt <= LocalDateTime.parse("2026-04-01T15:30:00"))
      } else {
        assertTrue(endAt.hour in 9..22)
      }
      assertContentEquals(generatedImage.bytes, client.uploadedBytes)
      assertEquals(generatedImage.fileName, client.uploadedFileName)
      assertEquals(generatedImage.mimeType, client.uploadedMimeType)
      assertEquals(5, result.summary?.termCount)
      assertContains(
          registry.scrape(),
          "ubaa_fallback_events_total{feature=\"ygdk\",operation=\"submit_clockin\",reason=\"ygdk_generated_photo\"}",
      )
    } finally {
      AppObservability.reset(registry)
      registry.close()
    }
  }

  @Test
  fun `submitClockin uses previous days when today has no full one hour window`() = runBlocking {
    val client = FakeYgdkClient()
    val service =
        YgdkService(
            clientProvider = { client },
            nowProvider = { LocalDateTime.parse("2026-04-01T08:30:00") },
            random = Random(0),
            imageGenerator =
                object : YgdkImageGenerator() {
                  override fun generate(): YgdkGeneratedImage {
                    return YgdkGeneratedImage(byteArrayOf(1), "transparent.png", "image/png")
                  }
                },
        )

    service.submitClockin("2418", YgdkClockinSubmitRequest())

    val startAt = assertNotNull(client.lastClockinStartAt)
    assertTrue(
        startAt.toLocalDate() in LocalDate.parse("2026-03-30")..LocalDate.parse("2026-03-31")
    )
    assertTrue(startAt.hour in 8..21)
  }

  @Test
  fun `submitClockin rejects incomplete time range`() = runBlocking {
    val service = YgdkService(clientProvider = { FakeYgdkClient() })

    val error =
        runCatching {
              service.submitClockin(
                  "2418",
                  YgdkClockinSubmitRequest(startTime = "2026-04-01 08:00"),
              )
            }
            .exceptionOrNull()

    val ygdkError = assertIs<YgdkException>(error)
    assertEquals("invalid_request", ygdkError.code)
    assertEquals("开始时间和结束时间需要同时填写", ygdkError.message)
  }

  private open class FakeYgdkClient(
      private val classifies: List<YgdkClassifyRaw> =
          listOf(YgdkClassifyRaw(classifyId = 3, name = "阳光体育", termNum = 16)),
      private val itemsByClassify: Map<Int, List<YgdkItemRaw>> =
          mapOf(
              3 to
                  listOf(
                      YgdkItemRaw(itemId = 1, name = "跑步", sort = 1),
                      YgdkItemRaw(itemId = 2, name = "健走", sort = 2),
                  )
          ),
      private val count: YgdkCountRaw = YgdkCountRaw(termCountShow = 3, termNum = 16),
      private val term: YgdkTermRaw = YgdkTermRaw(termId = 20261, name = "2026春"),
      private val records: YgdkRecordsPageRaw =
          YgdkRecordsPageRaw(
              records =
                  listOf(
                      YgdkRecordRaw(
                          recordId = 11,
                          itemId = 1,
                          itemName = "跑步",
                          startTime = 1_743_465_600,
                          endTime = 1_743_469_200,
                          place = "操场",
                          isOpen = false,
                          createTimeLabel = "2026-04-01 09:00",
                      )
                  ),
              total = 1,
          ),
      private val uploadedFile: YgdkUploadedFileRaw =
          YgdkUploadedFileRaw(fileName = "server-proof.png"),
      private val clockinResult: YgdkClockinResultRaw =
          YgdkClockinResultRaw(recordId = 77, termCountShow = 4, termNum = 16),
  ) : YgdkClient("2418", testSessionManager()) {
    var closed = false
      private set

    var uploadedBytes: ByteArray? = null
      private set

    var uploadedFileName: String? = null
      private set

    var uploadedMimeType: String? = null
      private set

    var lastClockinItemId: Int? = null
      private set

    var lastClockinItemName: String? = null
      private set

    var lastClockinPlace: String? = null
      private set

    var lastClockinOpen: Boolean = false
      private set

    var lastClockinStartAt: LocalDateTime? = null
      private set

    var lastClockinEndAt: LocalDateTime? = null
      private set

    override suspend fun getClassifyList(): List<YgdkClassifyRaw> = classifies

    override suspend fun getItemList(classifyId: Int): List<YgdkItemRaw> =
        itemsByClassify[classifyId].orEmpty()

    override suspend fun getCheckCount(classifyId: Int): YgdkCountRaw = count

    override suspend fun getTerm(): YgdkTermRaw = term

    override suspend fun getRecords(classifyId: Int, page: Int, limit: Int): YgdkRecordsPageRaw =
        records

    override suspend fun uploadImage(
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
    ): YgdkUploadedFileRaw {
      uploadedBytes = bytes
      uploadedFileName = fileName
      uploadedMimeType = mimeType
      return uploadedFile
    }

    override suspend fun clockin(
        classifyId: Int,
        itemId: Int,
        itemName: String,
        startAt: LocalDateTime,
        endAt: LocalDateTime,
        place: String,
        imageName: String,
        isOpen: Boolean,
        placeType: Int,
    ): YgdkClockinResultRaw {
      lastClockinItemId = itemId
      lastClockinItemName = itemName
      lastClockinPlace = place
      lastClockinOpen = isOpen
      lastClockinStartAt = startAt
      lastClockinEndAt = endAt
      return clockinResult
    }

    override fun close() {
      closed = true
    }
  }

  private class ExpiringYgdkClient : FakeYgdkClient() {
    override suspend fun getClassifyList(): List<YgdkClassifyRaw> {
      throw YgdkAuthenticationException()
    }
  }

  companion object {
    private fun testSessionManager(): SessionManager {
      return SessionManager(
          sessionStore = InMemorySessionStore(),
          cookieStorageFactory = InMemoryCookieStorageFactory(),
      )
    }
  }
}
