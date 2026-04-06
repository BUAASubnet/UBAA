package cn.edu.ubaa.model.dto

import kotlin.time.Clock
import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toInstant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class CgyyVenueSiteDto(
    val id: Int,
    val siteName: String,
    val venueName: String,
    val campusName: String,
    val seatCount: Int? = null,
    val reservationSpaceCount: Int? = null,
    val siteTelephone: String? = null,
    val openStartDate: String? = null,
    val openEndDate: String? = null,
)

@Serializable data class CgyyPurposeTypeDto(val key: Int, val name: String)

@Serializable
data class CgyyTimeSlotDto(
    val id: Int,
    val beginTime: String,
    val endTime: String,
    val label: String,
)

@Serializable
data class CgyySlotStatusDto(
    val timeId: Int,
    val reservationStatus: Int,
    val isReservable: Boolean,
    val startDate: String? = null,
    val endDate: String? = null,
    val tradeNo: String? = null,
    val orderId: Int? = null,
    val useNum: Int? = null,
    val alreadyNum: Int? = null,
    val takeUp: Boolean? = null,
    val takeUpExplain: String? = null,
)

@Serializable
data class CgyySpaceAvailabilityDto(
    val spaceId: Int,
    val spaceName: String,
    val venueSiteId: Int,
    val venueSpaceGroupId: Int? = null,
    val slots: List<CgyySlotStatusDto> = emptyList(),
)

@Serializable
data class CgyyDayInfoResponse(
    val venueSiteId: Int,
    val reservationDate: String,
    val availableDates: List<String> = emptyList(),
    val timeSlots: List<CgyyTimeSlotDto> = emptyList(),
    val spaces: List<CgyySpaceAvailabilityDto> = emptyList(),
    val reservationToken: String? = null,
    val reservationTotalNum: Int? = null,
)

@Serializable
data class CgyyReservationSelectionDto(
    val spaceId: Int,
    val timeId: Int,
    val venueSpaceGroupId: Int? = null,
)

@Serializable
data class CgyyReservationSubmitRequest(
    val venueSiteId: Int,
    val reservationDate: String,
    val selections: List<CgyyReservationSelectionDto>,
    val phone: String,
    val theme: String,
    val purposeType: Int,
    val joinerNum: Int,
    val activityContent: String,
    val joiners: String,
    val isPhilosophySocialSciences: Boolean = false,
    val isOffSchoolJoiner: Boolean = false,
)

@Serializable
data class CgyyOrderDto(
    val id: Int,
    val tradeNo: String? = null,
    val venueSiteId: Int? = null,
    val reservationDate: String? = null,
    val reservationDateDetail: String? = null,
    val venueSpaceName: String? = null,
    val campusName: String? = null,
    val venueName: String? = null,
    val siteName: String? = null,
    val reservationStartDate: String? = null,
    val reservationEndDate: String? = null,
    val phone: String? = null,
    val orderStatus: Int? = null,
    val payStatus: Int? = null,
    val checkStatus: Int? = null,
    val theme: String? = null,
    val purposeType: Int? = null,
    val purposeTypeName: String? = null,
    val joinerNum: Int? = null,
    val activityContent: String? = null,
    val joiners: String? = null,
    val checkContent: String? = null,
    val handleReason: String? = null,
    val remark: String? = null,
)

@Serializable
data class CgyyOrdersPageResponse(
    val content: List<CgyyOrderDto> = emptyList(),
    val totalElements: Int = 0,
    val totalPages: Int = 0,
    val size: Int = 20,
    val number: Int = 0,
)

@Serializable
data class CgyyReservationSubmitResponse(
    val success: Boolean,
    val message: String,
    val order: CgyyOrderDto? = null,
)

@Serializable data class CgyyLockCodeResponse(val rawData: JsonElement? = null)

enum class CgyyOrderDisplayColor {
  SUCCESS,
  ERROR,
  INFO,
  NEUTRAL,
}

data class CgyyOrderDisplayStatus(
    val primaryText: String,
    val detailText: String? = null,
    val color: CgyyOrderDisplayColor = CgyyOrderDisplayColor.NEUTRAL,
    val isCancelable: Boolean = true,
)

private object CgyyOrderStatusCode {
  const val NORMAL = 1
  const val CANCEL = 2
  const val OCCUPY = 3
}

private object CgyyOrderCheckStatusCode {
  const val PASS = 1
  const val FDY_PENDING = 2
  const val FDY_REJECTED = -2
  const val FSJ_PENDING = 3
  const val FSJ_REJECTED = -3
  const val XCB_PENDING = 4
  const val XCB_REJECTED = -4
  const val GJC_PENDING = 5
  const val GJC_REJECTED = -5
  const val JWC_PENDING = 6
  const val JWC_REJECTED = -6
}

private fun checkStatusDetailText(checkStatus: Int?): String? =
    when (checkStatus) {
      CgyyOrderCheckStatusCode.PASS -> "审批通过"
      CgyyOrderCheckStatusCode.FDY_PENDING -> "待辅导员审批"
      CgyyOrderCheckStatusCode.FDY_REJECTED -> "辅导员审批驳回"
      CgyyOrderCheckStatusCode.FSJ_PENDING -> "待副书记/副处长审批"
      CgyyOrderCheckStatusCode.FSJ_REJECTED -> "副书记/副处长审批驳回"
      CgyyOrderCheckStatusCode.XCB_PENDING -> "待宣传部审批"
      CgyyOrderCheckStatusCode.XCB_REJECTED -> "宣传部审批驳回"
      CgyyOrderCheckStatusCode.GJC_PENDING -> "待国交处备案"
      CgyyOrderCheckStatusCode.GJC_REJECTED -> "国交处备案驳回"
      CgyyOrderCheckStatusCode.JWC_PENDING -> "待教务处审批"
      CgyyOrderCheckStatusCode.JWC_REJECTED -> "教务处驳回"
      else -> null
    }

fun CgyyOrderDto.displayReservationDateText(): String {
  val dateOnly = reservationDate.normalizedText()
  reservationDateDetail?.normalizedText()?.let { detail ->
    if (detail.containsExplicitDate()) return detail
    val trimmedDetail = detail.withoutLeadingSpaceLabel(venueSpaceName, siteName)
    if (dateOnly != null && trimmedDetail.isNotBlank()) {
      return "$dateOnly $trimmedDetail"
    }
    if (dateOnly != null) return dateOnly
    return detail
  }

  val startDateTime = reservationStartDate.normalizedText()
  val endDateTime = reservationEndDate.normalizedText()
  if (startDateTime != null && endDateTime != null) {
    val startDate = startDateTime.substringBefore(" ")
    val startTime = startDateTime.substringAfter(" ", missingDelimiterValue = "")
    val endDate = endDateTime.substringBefore(" ")
    val endTime = endDateTime.substringAfter(" ", missingDelimiterValue = "")
    if (startDate == endDate && startTime.isNotBlank() && endTime.isNotBlank()) {
      return "$startDate $startTime - $endTime"
    }
    return "$startDateTime - $endDateTime"
  }

  startDateTime?.let {
    return it
  }
  dateOnly?.let {
    return it
  }
  return "日期待定"
}

fun CgyyOrderDto.displayStatus(): CgyyOrderDisplayStatus {
  val detailText = checkStatusDetailText(checkStatus)
  return when {
    (checkStatus ?: 0) < 0 ->
        CgyyOrderDisplayStatus(
            primaryText = detailText ?: "审批驳回",
            detailText = detailText,
            color = CgyyOrderDisplayColor.ERROR,
            isCancelable = false,
        )
    orderStatus == CgyyOrderStatusCode.CANCEL ->
        CgyyOrderDisplayStatus(
            primaryText = "已取消",
            color = CgyyOrderDisplayColor.ERROR,
            isCancelable = false,
        )
    orderStatus == CgyyOrderStatusCode.NORMAL && checkStatus == CgyyOrderCheckStatusCode.PASS ->
        CgyyOrderDisplayStatus(
            primaryText = "审批通过",
            detailText = detailText,
            color = CgyyOrderDisplayColor.SUCCESS,
            isCancelable = true,
        )
    orderStatus == CgyyOrderStatusCode.NORMAL && (checkStatus ?: 0) > 0 ->
        CgyyOrderDisplayStatus(
            primaryText = "待审批",
            detailText = detailText,
            color = CgyyOrderDisplayColor.INFO,
            isCancelable = true,
        )
    orderStatus == CgyyOrderStatusCode.OCCUPY ->
        CgyyOrderDisplayStatus(
            primaryText = "占用",
            color = CgyyOrderDisplayColor.NEUTRAL,
            isCancelable = true,
        )
    orderStatus == CgyyOrderStatusCode.NORMAL ->
        CgyyOrderDisplayStatus(
            primaryText = "正常",
            color = CgyyOrderDisplayColor.SUCCESS,
            isCancelable = true,
        )
    else ->
        CgyyOrderDisplayStatus(
            primaryText =
                buildString {
                  append("未知")
                  orderStatus?.let { append("($it)") }
                },
            detailText = detailText,
            color = CgyyOrderDisplayColor.NEUTRAL,
            isCancelable = false,
        )
  }
}

fun CgyyOrderDto.canCancelAt(
    now: Instant = Clock.System.now(),
    timeZone: TimeZone = TimeZone.currentSystemDefault(),
): Boolean {
  if (!displayStatus().isCancelable) return false

  val startDateTime = reservationStartDate.parseCgyyDateTime()
  if (startDateTime != null) {
    val cancelDeadline = startDateTime.toInstant(timeZone) - 4.hours
    return now < cancelDeadline
  }

  val endDateTime = reservationEndDate.parseCgyyDateTime()
  if (endDateTime != null) {
    return now < endDateTime.toInstant(timeZone)
  }

  return true
}

private fun String?.normalizedText(): String? =
    this?.trim()?.replace('T', ' ')?.takeIf { it.isNotEmpty() }

private fun String?.parseCgyyDateTime(): LocalDateTime? {
  val normalized = normalizedText() ?: return null
  return runCatching { LocalDateTime.parse(normalized.replace(" ", "T")) }.getOrNull()
}

private fun String.containsExplicitDate(): Boolean =
    contains('-') &&
        length >= 10 &&
        getOrNull(4) == '-' &&
        getOrNull(7) == '-' &&
        substring(0, 4).all(Char::isDigit)

private fun String.withoutLeadingSpaceLabel(vararg labels: String?): String {
  val normalized = trim()
  val matchedLabel =
      labels.mapNotNull { it.normalizedText() }.firstOrNull { normalized.startsWith(it) }
          ?: return normalized
  return normalized.removePrefix(matchedLabel).trimStart(' ', '/', '-', '>')
}
