package cn.edu.ubaa.cgyy

import cn.edu.ubaa.model.dto.CgyyDayInfoResponse
import cn.edu.ubaa.model.dto.CgyyLockCodeResponse
import cn.edu.ubaa.model.dto.CgyyOrderDto
import cn.edu.ubaa.model.dto.CgyyOrdersPageResponse
import cn.edu.ubaa.model.dto.CgyyPurposeTypeDto
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
import cn.edu.ubaa.model.dto.CgyyReservationSubmitResponse
import cn.edu.ubaa.model.dto.CgyySlotStatusDto
import cn.edu.ubaa.model.dto.CgyySpaceAvailabilityDto
import cn.edu.ubaa.model.dto.CgyyTimeSlotDto
import cn.edu.ubaa.model.dto.CgyyVenueSiteDto
import java.util.concurrent.ConcurrentHashMap
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class CgyyService(
    private val clientProvider: (String) -> CgyyGateway = ::CgyyZhjsClient,
    private val captchaSolver: CgyyCaptchaAutoSolver = CgyyCaptchaSolver(),
) {
  private data class CachedClient(
      val client: CgyyGateway,
      @Volatile var lastAccessAt: Long,
  )

  private val json = Json { ignoreUnknownKeys = true }
  private val clientCache = ConcurrentHashMap<String, CachedClient>()

  suspend fun getVenueSites(username: String): List<CgyyVenueSiteDto> {
    return getClient(username).getVenueSites().map { mapVenueSite(it.jsonObject) }
  }

  suspend fun getPurposeTypes(username: String): List<CgyyPurposeTypeDto> {
    val dynamic =
        runCatching { parsePurposeTypes(getClient(username).getPurposeTypesRaw()) }.getOrNull()
    return if (!dynamic.isNullOrEmpty()) dynamic else fallbackPurposeTypes()
  }

  suspend fun getDayInfo(username: String, venueSiteId: Int, date: String): CgyyDayInfoResponse {
    return mapDayInfo(
        venueSiteId = venueSiteId,
        reservationDate = date,
        raw = getClient(username).getReservationDayInfo(date, venueSiteId),
    )
  }

  suspend fun submitReservation(
      username: String,
      request: CgyyReservationSubmitRequest,
  ): CgyyReservationSubmitResponse {
    validateRequest(request)

    val client = getClient(username)
    val dayInfo = getDayInfo(username, request.venueSiteId, request.reservationDate)
    val reservationToken =
        dayInfo.reservationToken
            ?: throw CgyyException("预约上下文 token 缺失，请刷新后重试", "reservation_token_missing")

    val selectedSpaceId = request.selections.first().spaceId
    val selectedSpace =
        dayInfo.spaces.firstOrNull { it.spaceId == selectedSpaceId }
            ?: throw CgyyException("所选房间不存在或已失效", "reservation_invalid")
    if (request.selections.any { it.spaceId != selectedSpaceId }) {
      throw CgyyException("同次预约只能选择同一房间的时段", "reservation_invalid")
    }

    request.selections.forEach { selection ->
      val slot =
          selectedSpace.slots.firstOrNull { it.timeId == selection.timeId }
              ?: throw CgyyException("所选时段不存在或已失效", "reservation_invalid")
      if (!slot.isReservable) {
        throw CgyyException("所选时段已不可预约，请刷新后重试", "reservation_invalid")
      }
    }

    val reservationOrderJson = json.encodeToString(request.selections)
    client.createReservationOrder(
        venueSiteId = request.venueSiteId,
        reservationDate = request.reservationDate,
        weekStartDate = request.reservationDate,
        reservationOrderJson = reservationOrderJson,
        token = reservationToken,
    )

    var lastCaptchaError: Exception? = null
    repeat(3) {
      try {
        val challenge = client.getCaptcha()
        val solved = captchaSolver.solve(challenge)
        client.verifyCaptcha(solved.pointJson, challenge.token)
        val submitResponse =
            client.submitReservationOrder(
                venueSiteId = request.venueSiteId,
                reservationDate = request.reservationDate,
                reservationOrderJson = reservationOrderJson,
                weekStartDate = request.reservationDate,
                phone = request.phone.trim(),
                theme = request.theme.trim(),
                purposeType = request.purposeType,
                joinerNum = request.joinerNum,
                activityContent = request.activityContent.trim(),
                joiners = request.joiners.trim(),
                captchaVerification = solved.captchaVerification,
                token = reservationToken,
                isPhilosophySocialSciences = if (request.isPhilosophySocialSciences) 1 else 0,
                isOffSchoolJoiner = if (request.isOffSchoolJoiner) 1 else 0,
            )
        val order =
            submitResponse.data?.jsonObject?.get("orderInfo")?.jsonObject?.let { mapOrder(it) }
        return CgyyReservationSubmitResponse(
            success = true,
            message = submitResponse.message.ifBlank { "预约成功" },
            order = order,
        )
      } catch (e: Exception) {
        lastCaptchaError = e
      }
    }

    throw CgyyException(
        lastCaptchaError?.message ?: "验证码识别失败，请稍后重试",
        "captcha_error",
    )
  }

  suspend fun getOrders(username: String, page: Int, size: Int): CgyyOrdersPageResponse {
    val data = getClient(username).getMineOrders(page, size)
    return CgyyOrdersPageResponse(
        content = data["content"]?.jsonArray?.map { mapOrder(it.jsonObject) } ?: emptyList(),
        totalElements = data["totalElements"]?.jsonPrimitive?.intOrNull ?: 0,
        totalPages = data["totalPages"]?.jsonPrimitive?.intOrNull ?: 0,
        size = data["size"]?.jsonPrimitive?.intOrNull ?: size,
        number = data["number"]?.jsonPrimitive?.intOrNull ?: page,
    )
  }

  suspend fun getOrderDetail(username: String, orderId: Int): CgyyOrderDto {
    return mapOrder(getClient(username).getOrderDetail(orderId))
  }

  suspend fun cancelOrder(username: String, orderId: Int): CgyyReservationSubmitResponse {
    val response = getClient(username).cancelOrder(orderId)
    return CgyyReservationSubmitResponse(
        success = true,
        message = response.message.ifBlank { "取消成功" },
        order = null,
    )
  }

  suspend fun getLockCode(username: String): CgyyLockCodeResponse {
    return CgyyLockCodeResponse(rawData = getClient(username).getLockCode())
  }

  fun cleanupExpiredClients(maxIdleMillis: Long = DEFAULT_MAX_IDLE_MILLIS): Int {
    val cutoff = System.currentTimeMillis() - maxIdleMillis
    var removed = 0
    for ((username, cached) in clientCache.entries.toList()) {
      if (cached.lastAccessAt >= cutoff) continue
      if (!clientCache.remove(username, cached)) continue
      cached.client.close()
      removed++
    }
    return removed
  }

  fun cacheSize(): Int = clientCache.size

  fun clearCache() {
    clientCache.values.forEach { it.client.close() }
    clientCache.clear()
  }

  private fun getClient(username: String): CgyyGateway {
    val now = System.currentTimeMillis()
    return clientCache
        .compute(username) { _, existing ->
          existing?.also { it.lastAccessAt = now } ?: CachedClient(clientProvider(username), now)
        }!!
        .client
  }

  private fun validateRequest(request: CgyyReservationSubmitRequest) {
    if (request.selections.isEmpty()) throw CgyyException("请至少选择一个时段", "invalid_request")
    if (request.phone.isBlank()) throw CgyyException("请填写联系电话", "invalid_request")
    if (request.theme.isBlank()) throw CgyyException("请填写活动主题", "invalid_request")
    if (request.joinerNum <= 0) throw CgyyException("参与人数必须大于 0", "invalid_request")
    if (request.activityContent.isBlank()) throw CgyyException("请填写活动内容", "invalid_request")
    if (request.joiners.isBlank()) throw CgyyException("请填写参与人说明", "invalid_request")
  }

  private fun mapVenueSite(raw: JsonObject): CgyyVenueSiteDto {
    return CgyyVenueSiteDto(
        id = raw["id"]?.jsonPrimitive?.intOrNull ?: 0,
        siteName = raw.string("siteName"),
        venueName = raw.string("venueName"),
        campusName = raw.string("campusName"),
        seatCount = raw["seatCount"]?.jsonPrimitive?.intOrNull,
        reservationSpaceCount = raw["reservationSpaceCount"]?.jsonPrimitive?.intOrNull,
        siteTelephone = raw["siteTelephone"]?.jsonPrimitive?.contentOrNull,
        openStartDate = raw["openStartDate"]?.jsonPrimitive?.contentOrNull,
        openEndDate = raw["openEndDate"]?.jsonPrimitive?.contentOrNull,
    )
  }

  private fun mapDayInfo(
      venueSiteId: Int,
      reservationDate: String,
      raw: JsonObject,
  ): CgyyDayInfoResponse {
    val timeSlots =
        raw["spaceTimeInfo"]?.jsonArray?.mapNotNull { element ->
          val slot = element.jsonObject
          val id = slot["id"]?.jsonPrimitive?.intOrNull ?: return@mapNotNull null
          val begin = slot["beginTime"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
          val end = slot["endTime"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
          CgyyTimeSlotDto(id = id, beginTime = begin, endTime = end, label = "$begin-$end")
        } ?: emptyList()
    val timeSlotIds = timeSlots.map { it.id }.toSet()
    val reservationDateSpaceInfo = raw["reservationDateSpaceInfo"]?.jsonObject
    val dateKey =
        when {
          reservationDateSpaceInfo?.containsKey(reservationDate) == true -> reservationDate
          else -> reservationDateSpaceInfo?.keys?.firstOrNull() ?: reservationDate
        }
    val spaces =
        reservationDateSpaceInfo
            ?.get(dateKey)
            ?.jsonArray
            ?.map { element ->
              val space = element.jsonObject
              val spaceId = space["id"]?.jsonPrimitive?.intOrNull ?: 0
              val venueSpaceGroupId = space["venueSpaceGroupId"]?.jsonPrimitive?.intOrNull
              CgyySpaceAvailabilityDto(
                  spaceId = spaceId,
                  spaceName = space.string("spaceName"),
                  venueSiteId = space["venueSiteId"]?.jsonPrimitive?.intOrNull ?: venueSiteId,
                  venueSpaceGroupId = venueSpaceGroupId,
                  slots =
                      timeSlots.mapNotNull { slot ->
                        val rawSlot =
                            space[slot.id.toString()]?.jsonObject ?: return@mapNotNull null
                        mapSlot(slot.id, rawSlot)
                      },
              )
            }
            ?.sortedBy { it.spaceName } ?: emptyList()
    return CgyyDayInfoResponse(
        venueSiteId = venueSiteId,
        reservationDate = dateKey,
        availableDates =
            raw["ableReservationDateList"]?.jsonArray?.toStringList()
                ?: raw["reservationDateList"]?.jsonArray?.toStringList().orEmpty(),
        timeSlots = timeSlots,
        spaces =
            spaces.map { space ->
              space.copy(
                  slots = space.slots.filter { it.timeId in timeSlotIds }.sortedBy { it.timeId }
              )
            },
        reservationToken = raw["token"]?.jsonPrimitive?.contentOrNull,
        reservationTotalNum = raw["reservationTotalNum"]?.jsonPrimitive?.intOrNull,
    )
  }

  private fun mapSlot(timeId: Int, raw: JsonObject): CgyySlotStatusDto {
    val reservationStatus = raw["reservationStatus"]?.jsonPrimitive?.intOrNull ?: 0
    val tradeNo = raw["tradeNo"]?.jsonPrimitive?.contentOrNull
    val orderId = raw["orderId"]?.jsonPrimitive?.intOrNull
    val takeUp = raw["takeUp"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull()
    val isReservable =
        reservationStatus == 1 && tradeNo == null && orderId == null && takeUp != true
    return CgyySlotStatusDto(
        timeId = timeId,
        reservationStatus = reservationStatus,
        isReservable = isReservable,
        startDate = raw["startDate"]?.jsonPrimitive?.contentOrNull,
        endDate = raw["endDate"]?.jsonPrimitive?.contentOrNull,
        tradeNo = tradeNo,
        orderId = orderId,
        useNum = raw["useNum"]?.jsonPrimitive?.intOrNull,
        alreadyNum = raw["alreadyNum"]?.jsonPrimitive?.intOrNull,
        takeUp = takeUp,
        takeUpExplain = raw["takeUpExplain"]?.jsonPrimitive?.contentOrNull,
    )
  }

  private fun mapOrder(raw: JsonObject): CgyyOrderDto {
    val purposeType = raw["purposeType"]?.jsonPrimitive?.intOrNull
    return CgyyOrderDto(
        id = raw["id"]?.jsonPrimitive?.intOrNull ?: 0,
        tradeNo = raw["tradeNo"]?.jsonPrimitive?.contentOrNull,
        venueSiteId = raw["venueSiteId"]?.jsonPrimitive?.intOrNull,
        reservationDate = raw["reservationDate"]?.jsonPrimitive?.contentOrNull,
        reservationDateDetail = raw["reservationDateDetail"]?.jsonPrimitive?.contentOrNull,
        venueSpaceName = raw["venueSpaceName"]?.jsonPrimitive?.contentOrNull,
        campusName = raw["campusName"]?.jsonPrimitive?.contentOrNull,
        venueName = raw["venueName"]?.jsonPrimitive?.contentOrNull,
        siteName = raw["siteName"]?.jsonPrimitive?.contentOrNull,
        reservationStartDate = raw["reservationStartDate"]?.jsonPrimitive?.contentOrNull,
        reservationEndDate = raw["reservationEndDate"]?.jsonPrimitive?.contentOrNull,
        phone = raw["phone"]?.jsonPrimitive?.contentOrNull,
        orderStatus = raw["orderStatus"]?.jsonPrimitive?.intOrNull,
        payStatus = raw["payStatus"]?.jsonPrimitive?.intOrNull,
        checkStatus = raw["checkStatus"]?.jsonPrimitive?.intOrNull,
        theme = raw["theme"]?.jsonPrimitive?.contentOrNull,
        purposeType = purposeType,
        purposeTypeName = purposeType?.let { purposeTypeName(it) },
        joinerNum = raw["joinerNum"]?.jsonPrimitive?.intOrNull,
        activityContent = raw["activityContent"]?.jsonPrimitive?.contentOrNull,
        joiners = raw["joiners"]?.jsonPrimitive?.contentOrNull,
        checkContent = raw["checkContent"]?.jsonPrimitive?.contentOrNull,
        handleReason = raw["handleReason"]?.jsonPrimitive?.contentOrNull,
        remark = raw["remark"]?.jsonPrimitive?.contentOrNull,
    )
  }

  private fun parsePurposeTypes(raw: JsonElement?): List<CgyyPurposeTypeDto> {
    val results = linkedMapOf<Int, String>()

    fun traverse(element: JsonElement?) {
      when (element) {
        null -> Unit
        is JsonArray -> element.forEach(::traverse)
        is JsonObject -> {
          val name = element["name"]?.jsonPrimitive?.contentOrNull
          val key =
              element["key"]?.jsonPrimitive?.intOrNull
                  ?: element["value"]?.jsonPrimitive?.intOrNull
                  ?: element["id"]?.jsonPrimitive?.intOrNull
          if (key != null && !name.isNullOrBlank() && name.contains("类")) {
            results.putIfAbsent(key, name)
          }
          element.values.forEach(::traverse)
        }
        else -> Unit
      }
    }

    traverse(raw)
    return results.entries.map { CgyyPurposeTypeDto(it.key, it.value) }.sortedBy { it.key }
  }

  private fun fallbackPurposeTypes(): List<CgyyPurposeTypeDto> {
    return listOf(
        CgyyPurposeTypeDto(1, "导学活动类"),
        CgyyPurposeTypeDto(2, "学业支持类（串讲、答疑、学习小组讨论等）"),
        CgyyPurposeTypeDto(3, "学术研讨类（竞赛、答辩、展示等小组讨论）"),
        CgyyPurposeTypeDto(4, "党建活动类"),
        CgyyPurposeTypeDto(5, "工作会议类（单位工作例会、学生组织工作会议等）"),
        CgyyPurposeTypeDto(6, "团队建设类（班级、社团、学生会等学生组织团建）"),
        CgyyPurposeTypeDto(7, "培训面试类（梦拓、学生组织培训及面试等）"),
        CgyyPurposeTypeDto(8, "博雅课程类"),
        CgyyPurposeTypeDto(9, "讲座、沙龙研讨类"),
        CgyyPurposeTypeDto(10, "其他特色活动类"),
    )
  }

  private fun purposeTypeName(key: Int): String? =
      fallbackPurposeTypes().firstOrNull { it.key == key }?.name

  private fun JsonArray.toStringList(): List<String> = mapNotNull {
    it.jsonPrimitive.contentOrNull?.takeIf(String::isNotBlank)
  }

  private fun JsonObject.string(key: String): String =
      this[key]?.jsonPrimitive?.contentOrNull.orEmpty()

  companion object {
    private const val DEFAULT_MAX_IDLE_MILLIS = 30 * 60 * 1000L
  }
}

object GlobalCgyyService {
  val instance: CgyyService by lazy { CgyyService() }
}
