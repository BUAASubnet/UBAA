package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.SpocAssignmentDetailDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import io.ktor.http.Url
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.time.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive

internal open class LocalSpocException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause)

internal class LocalSpocAuthenticationException(message: String) : LocalSpocException(message)

internal data class LocalSpocLoginTokens(
    val token: String,
    val refreshToken: String? = null,
)

@OptIn(ExperimentalEncodingApi::class)
internal object LocalSpocCrypto {
  private val keyBytes = "inco12345678ocni".encodeToByteArray()
  private val ivBytes = "ocni12345678inco".encodeToByteArray()
  private const val blockSize = 16

  fun encryptParam(plainText: String): String {
    val plainBytes = plainText.encodeToByteArray()
    val padded = plainBytes + ByteArray((blockSize - plainBytes.size % blockSize) % blockSize)
    return Base64.encode(PlatformAesCbcNoPadding.encrypt(padded, keyBytes, ivBytes))
  }

  fun decryptParam(cipherTextBase64: String): String {
    val encrypted = Base64.decode(cipherTextBase64)
    val decrypted = PlatformAesCbcNoPadding.decrypt(encrypted, keyBytes, ivBytes)
    val endExclusive = decrypted.indexOfLast { it != 0.toByte() } + 1
    return decrypted.copyOf(endExclusive.coerceAtLeast(0)).decodeToString()
  }
}

internal object LocalSpocParsers {
  private val chinaTimeZone = TimeZone.of("Asia/Shanghai")

  fun extractLoginTokens(url: String): LocalSpocLoginTokens? {
    val parsed = runCatching { Url(url) }.getOrNull() ?: return null
    if (!parsed.encodedPath.contains("/spocnew/cas")) return null
    val token = parsed.parameters["token"]?.takeIf { it.isNotBlank() } ?: return null
    val refreshToken = parsed.parameters["refreshToken"]?.takeIf { it.isNotBlank() }
    return LocalSpocLoginTokens(token = token, refreshToken = refreshToken)
  }

  fun resolveRoleCode(content: LocalSpocCasLoginContent): String? {
    return content.jsdm?.takeIf { it.isNotBlank() }
        ?: firstString(content.rolecode)
        ?: firstString(content.jsdmList)
  }

  fun toPlainText(html: String?): String? {
    if (html.isNullOrBlank()) return null
    return html
        .replace(Regex("(?i)<br\\s*/?>"), " ")
        .replace(Regex("<[^>]+>"), " ")
        .decodeHtmlEntities()
        .replace(Regex("\\s+"), " ")
        .trim()
        .ifBlank { null }
  }

  fun mapSubmissionStatus(rawStatus: String?, hasContent: Boolean): SpocSubmissionStatus {
    return when (rawStatus?.trim()) {
      "1",
      "已做",
      "已提交" -> SpocSubmissionStatus.SUBMITTED
      "0",
      "未做",
      "未提交" -> SpocSubmissionStatus.UNSUBMITTED
      else -> if (!hasContent) SpocSubmissionStatus.UNSUBMITTED else SpocSubmissionStatus.UNKNOWN
    }
  }

  fun submissionStatusText(status: SpocSubmissionStatus, rawStatus: String? = null): String {
    return when (status) {
      SpocSubmissionStatus.SUBMITTED -> "已提交"
      SpocSubmissionStatus.UNSUBMITTED -> "未提交"
      SpocSubmissionStatus.UNKNOWN ->
          rawStatus?.takeIf { it.isNotBlank() }?.let { "未知状态($it)" } ?: "未知状态"
    }
  }

  fun normalizeScore(rawScore: String?): String? {
    val normalized = rawScore?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return Regex("""-?\d+(?:\.\d+)?""").find(normalized)?.value ?: normalized
  }

  fun normalizeDateTime(rawValue: String?): String? {
    val normalized = rawValue?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    return runCatching { Instant.parse(normalized).toLocalDateTime(chinaTimeZone).toSpocDateTimeText() }
        .getOrElse { normalized.replace('T', ' ').substringBefore('.') }
  }

  private fun firstString(element: JsonElement?): String? {
    return when (element) {
      null -> null
      is JsonPrimitive -> element.contentOrNull?.takeIf { it.isNotBlank() }
      else ->
          element.jsonArray.firstNotNullOfOrNull {
            it.jsonPrimitive.contentOrNull?.takeIf { value -> value.isNotBlank() }
          }
    }
  }

  private fun String.decodeHtmlEntities(): String =
      replace("&nbsp;", " ")
          .replace("&amp;", "&")
          .replace("&lt;", "<")
          .replace("&gt;", ">")
          .replace("&quot;", "\"")
          .replace("&#39;", "'")
          .replace("&#x27;", "'")
}

internal fun SpocAssignmentSummaryDto.toLocalSpocDetail(
    contentPlainText: String?,
    contentHtml: String?,
    submittedAt: String?,
): SpocAssignmentDetailDto {
  return SpocAssignmentDetailDto(
      assignmentId = assignmentId,
      courseId = courseId,
      courseName = courseName,
      teacherName = teacherName,
      title = title,
      startTime = startTime,
      dueTime = dueTime,
      score = score,
      submissionStatus = submissionStatus,
      submissionStatusText = submissionStatusText,
      contentPlainText = contentPlainText,
      contentHtml = contentHtml,
      submittedAt = submittedAt,
  )
}

@Serializable
internal data class LocalSpocEnvelope<T>(
    val code: Int,
    val msg: String? = null,
    @SerialName("msg_en") val msgEn: String? = null,
    val content: T? = null,
)

@Serializable internal data class LocalSpocCasLoginRequest(val token: String)

@Serializable internal data class LocalSpocQueryOneRequest(val param: String)

@Serializable internal data class LocalSpocEncryptedParamRequest(val param: String)

@Serializable
internal data class LocalSpocAssignmentsPageRequest(
    val pageSize: Int,
    val pageNum: Int,
    val sqlid: String,
    val xnxq: String,
    val kcid: String = "",
    val yzwz: String = "",
)

@Serializable
internal data class LocalSpocCurrentTermContent(
    val dqxq: String? = null,
    val mrxq: String? = null,
)

@Serializable
internal data class LocalSpocCourseRaw(
    val kcid: String,
    val kcmc: String,
    val skjs: String? = null,
)

@Serializable
internal data class LocalSpocAssignmentDetailRaw(
    val id: String,
    val zymc: String,
    val zynr: String? = null,
    val zykssj: String? = null,
    val zyjzsj: String? = null,
    val zyfs: String? = null,
    val sskcid: String? = null,
)

@Serializable
internal data class LocalSpocSubmissionRaw(
    val tjzt: String? = null,
    val tjsj: String? = null,
)

@Serializable
internal data class LocalSpocAssignmentsPageContent(
    val total: Int = 0,
    val list: List<LocalSpocPagedAssignmentRaw> = emptyList(),
    val pageNum: Int = 1,
    val pageSize: Int = 15,
    val pages: Int = 1,
    val hasNextPage: Boolean = false,
)

@Serializable
internal data class LocalSpocPagedAssignmentRaw(
    val zyid: String,
    val tjzt: String? = null,
    val zyjzsj: String? = null,
    val zymc: String,
    val zykssj: String? = null,
    val sskcid: String? = null,
    val xnxq: String? = null,
    val mf: String? = null,
    val kcmc: String? = null,
)

@Serializable
internal data class LocalSpocCasLoginContent(
    val jsdm: String? = null,
    val rolecode: JsonElement? = null,
    val jsdmList: JsonElement? = null,
)

private fun kotlinx.datetime.LocalDateTime.toSpocDateTimeText(): String =
    "${date.year}-${(date.month.ordinal + 1).toString().padStart(2, '0')}-${date.day.toString().padStart(2, '0')} " +
        "${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}:${second.toString().padStart(2, '0')}"
