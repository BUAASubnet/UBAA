package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.serialization.json.Json

class LocalSpocSupportTest {
  private val json = Json
  private val encryptedAssignmentsPageParam =
      "hkJ9jAFVEMFUgJEjbOLv4eRZqXHIsmF+WbYaG1ipT1L1N+BbxRXtBj6Gcjri4Mo+y6q22/FkNm/isiC2+B+/hNejBx2cQJfNp9zoxorVJBa86sID0ROtPQ/2V07JCmVC3qsgIWBokL7EYyiPfilw+0ryJ6e61jRnLn90sQFosew="
  private val plainAssignmentsPageParam =
      """{"pageSize":15,"pageNum":1,"sqlid":"1713252980496efac7d5d9985e81693116d3e8a52ebf2b","xnxq":"2025-20262","kcid":"","yzwz":""}"""

  @Test
  fun `extract login tokens from cas redirect url`() {
    val tokens =
        LocalSpocParsers.extractLoginTokens(
            "https://spoc.buaa.edu.cn/spocnew/cas?token=test-token&refreshToken=test-refresh"
        )

    assertEquals("test-token", tokens?.token)
    assertEquals("test-refresh", tokens?.refreshToken)
  }

  @Test
  fun `extract login tokens returns null for unrelated url`() {
    val tokens = LocalSpocParsers.extractLoginTokens("https://spoc.buaa.edu.cn/spocnewht/index")

    assertNull(tokens)
  }

  @Test
  fun `resolve role code prefers jsdm then rolecode then jsdmList`() {
    val fromJsdm =
        LocalSpocCasLoginContent(
            jsdm = "01",
            rolecode = json.parseToJsonElement("""["02"]"""),
            jsdmList = json.parseToJsonElement("""["03"]"""),
        )
    val fromRoleCode =
        LocalSpocCasLoginContent(
            jsdm = null,
            rolecode = json.parseToJsonElement("""["02"]"""),
            jsdmList = json.parseToJsonElement("""["03"]"""),
        )
    val fromJsdmList =
        LocalSpocCasLoginContent(
            jsdm = null,
            rolecode = null,
            jsdmList = json.parseToJsonElement("""["03"]"""),
        )

    assertEquals("01", LocalSpocParsers.resolveRoleCode(fromJsdm))
    assertEquals("02", LocalSpocParsers.resolveRoleCode(fromRoleCode))
    assertEquals("03", LocalSpocParsers.resolveRoleCode(fromJsdmList))
  }

  @Test
  fun `spoc crypto decrypts known example`() {
    assertEquals(
        plainAssignmentsPageParam,
        LocalSpocCrypto.decryptParam(encryptedAssignmentsPageParam),
    )
  }

  @Test
  fun `spoc crypto encrypts known example`() {
    assertEquals(
        encryptedAssignmentsPageParam,
        LocalSpocCrypto.encryptParam(plainAssignmentsPageParam),
    )
  }

  @Test
  fun `map submission status handles known and unknown cases`() {
    assertEquals(
        SpocSubmissionStatus.UNSUBMITTED,
        LocalSpocParsers.mapSubmissionStatus(rawStatus = null, hasContent = false),
    )
    assertEquals(
        SpocSubmissionStatus.SUBMITTED,
        LocalSpocParsers.mapSubmissionStatus(rawStatus = "1", hasContent = true),
    )
    assertEquals(
        SpocSubmissionStatus.UNSUBMITTED,
        LocalSpocParsers.mapSubmissionStatus(rawStatus = "0", hasContent = true),
    )
    assertEquals(
        SpocSubmissionStatus.UNKNOWN,
        LocalSpocParsers.mapSubmissionStatus(rawStatus = "9", hasContent = true),
    )
    assertEquals(
        SpocSubmissionStatus.SUBMITTED,
        LocalSpocParsers.mapSubmissionStatus(rawStatus = "已做", hasContent = true),
    )
    assertEquals(
        SpocSubmissionStatus.UNSUBMITTED,
        LocalSpocParsers.mapSubmissionStatus(rawStatus = "未做", hasContent = true),
    )
  }

  @Test
  fun `normalize score strips display prefix`() {
    assertEquals("100", LocalSpocParsers.normalizeScore("满分:100"))
    assertEquals("0", LocalSpocParsers.normalizeScore("满分:0"))
    assertEquals("98.5", LocalSpocParsers.normalizeScore("98.5"))
    assertNull(LocalSpocParsers.normalizeScore(null))
  }

  @Test
  fun `normalize datetime converts iso offset to legacy format`() {
    assertEquals(
        "2026-03-31 23:59:59",
        LocalSpocParsers.normalizeDateTime("2026-03-31T15:59:59.000+00:00"),
    )
    assertEquals(
        "2026-03-24 16:00:00",
        LocalSpocParsers.normalizeDateTime("2026-03-24T08:00:00.000+00:00"),
    )
    assertEquals(
        "2026-03-24 16:00:00",
        LocalSpocParsers.normalizeDateTime("2026-03-24 16:00:00"),
    )
  }

  @Test
  fun `html sanitizer returns readable plain text`() {
    val plainText =
        LocalSpocParsers.toPlainText(
            "<h4>&nbsp;Lab1</h4>\n<p>- Solve a real-world problem.</p><p>- Parallelize it in R/Python.</p>"
        )

    assertEquals("Lab1 - Solve a real-world problem. - Parallelize it in R/Python.", plainText)
  }
}
