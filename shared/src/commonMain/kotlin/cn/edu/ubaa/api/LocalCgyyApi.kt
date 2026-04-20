package cn.edu.ubaa.api

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
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import io.ktor.http.Url
import kotlin.time.Clock
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

internal class LocalCgyyApiBackend(
    private val captchaSolver: LocalCgyyCaptchaSolver = DefaultLocalCgyyCaptchaSolver(),
) : CgyyApiBackend {
  private val json = Json { ignoreUnknownKeys = true }
  private val clientMutex = Mutex()
  private val clientCache = mutableMapOf<String, LocalCgyyClient>()

  override suspend fun getVenueSites(): Result<List<CgyyVenueSiteDto>> =
      execute("研讨室场地列表加载失败，请稍后重试") { _, client ->
        client.getVenueSites().map { mapVenueSite(it.jsonObject) }
      }

  override suspend fun getPurposeTypes(): Result<List<CgyyPurposeTypeDto>> =
      execute("研讨室活动类型加载失败，请稍后重试") { _, client ->
        parsePurposeTypes(client.getPurposeTypesRaw()).ifEmpty { fallbackPurposeTypes() }
      }

  override suspend fun getDayInfo(
      venueSiteId: Int,
      date: String,
  ): Result<CgyyDayInfoResponse> =
      execute("研讨室可预约信息加载失败，请稍后重试") { _, client ->
        mapDayInfo(
            venueSiteId = venueSiteId,
            reservationDate = date,
            raw = client.getReservationDayInfo(date, venueSiteId),
        )
      }

  override suspend fun submitReservation(
      request: CgyyReservationSubmitRequest
  ): Result<CgyyReservationSubmitResponse> =
      execute("研讨室预约提交失败，请稍后重试") { _, client ->
        validateRequest(request)

        val dayInfo = getDayInfo(request.venueSiteId, request.reservationDate).getOrThrow()
        val reservationToken =
            dayInfo.reservationToken
                ?: throw LocalCgyyApiException(
                    "预约上下文 token 缺失，请刷新后重试",
                    "reservation_token_missing",
                    HttpStatusCode.BadRequest,
                )
        val selectedSpaceId = request.selections.first().spaceId
        val selectedSpace =
            dayInfo.spaces.firstOrNull { it.spaceId == selectedSpaceId }
                ?: throw LocalCgyyApiException(
                    "所选房间不存在或已失效",
                    "reservation_invalid",
                    HttpStatusCode.BadRequest,
                )
        if (request.selections.any { it.spaceId != selectedSpaceId }) {
          throw LocalCgyyApiException(
              "同次预约只能选择同一房间的时段",
              "reservation_invalid",
              HttpStatusCode.BadRequest,
          )
        }

        request.selections.forEach { selection ->
          val slot =
              selectedSpace.slots.firstOrNull { it.timeId == selection.timeId }
                  ?: throw LocalCgyyApiException(
                      "所选时段不存在或已失效",
                      "reservation_invalid",
                      HttpStatusCode.BadRequest,
                  )
          if (!slot.isReservable) {
            throw LocalCgyyApiException(
                "所选时段已不可预约，请刷新后重试",
                "reservation_invalid",
                HttpStatusCode.BadRequest,
            )
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
        repeat(3) { attempt ->
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
                submitResponse.data?.jsonObject?.get("orderInfo")?.jsonObject?.let(::mapOrder)
            return@execute CgyyReservationSubmitResponse(
                success = true,
                message = submitResponse.message.ifBlank { "预约成功" },
                order = order,
            )
          } catch (error: Exception) {
            lastCaptchaError = error
            if (attempt == 2) {
              throw LocalCgyyApiException(
                  error.message ?: "验证码识别失败，请稍后重试",
                  "captcha_error",
                  HttpStatusCode.BadGateway,
              )
            }
          }
        }

        error("unreachable")
      }

  override suspend fun getMyOrders(page: Int, size: Int): Result<CgyyOrdersPageResponse> =
      execute("研讨室预约列表加载失败，请稍后重试") { _, client ->
        val data = client.getMineOrders(page, size)
        CgyyOrdersPageResponse(
            content = data["content"]?.jsonArray?.map { mapOrder(it.jsonObject) } ?: emptyList(),
            totalElements = data["totalElements"]?.jsonPrimitive?.intOrNull ?: 0,
            totalPages = data["totalPages"]?.jsonPrimitive?.intOrNull ?: 0,
            size = data["size"]?.jsonPrimitive?.intOrNull ?: size,
            number = data["number"]?.jsonPrimitive?.intOrNull ?: page,
        )
      }

  override suspend fun getOrderDetail(orderId: Int): Result<CgyyOrderDto> =
      execute("研讨室预约详情加载失败，请稍后重试") { _, client -> mapOrder(client.getOrderDetail(orderId)) }

  override suspend fun cancelOrder(orderId: Int): Result<CgyyReservationSubmitResponse> =
      execute("研讨室预约取消失败，请稍后重试") { _, client ->
        val response = client.cancelOrder(orderId)
        CgyyReservationSubmitResponse(
            success = true,
            message = response.message.ifBlank { "取消成功" },
            order = null,
        )
      }

  override suspend fun getLockCode(): Result<CgyyLockCodeResponse> =
      execute("研讨室门锁密码加载失败，请稍后重试") { _, client ->
        CgyyLockCodeResponse(rawData = client.getLockCode())
      }

  private suspend fun currentClient(username: String): LocalCgyyClient =
      clientMutex.withLock { clientCache.getOrPut(username) { LocalCgyyClient(username) } }

  private suspend fun <T> execute(
      defaultMessage: String,
      block: suspend (String, LocalCgyyClient) -> T,
  ): Result<T> {
    val session =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val username = session.user.schoolid.ifBlank { session.username }
    if (username.isBlank()) return Result.failure(localUnauthenticatedApiException())
    return try {
      Result.success(block(username, currentClient(username)))
    } catch (error: Exception) {
      Result.failure(mapFailure(error, defaultMessage))
    }
  }

  private suspend fun mapFailure(error: Exception, defaultMessage: String): Exception =
      when (error) {
        is LocalCgyyApiException ->
            if (error.code == "unauthenticated") {
              resolveLocalBusinessAuthenticationFailure("cgyy_error")
            } else {
              ApiCallException(
                  message = userFacingMessageForCode(error.code, error.status),
                  status = error.status,
                  code = error.code,
              )
            }
        is ApiCallException -> error
        else -> error.toUserFacingApiException(defaultMessage)
      }

  private fun validateRequest(request: CgyyReservationSubmitRequest) {
    if (request.selections.isEmpty()) {
      throw LocalCgyyApiException("请至少选择一个时段", "invalid_request", HttpStatusCode.BadRequest)
    }
    if (request.phone.isBlank()) {
      throw LocalCgyyApiException("请填写联系电话", "invalid_request", HttpStatusCode.BadRequest)
    }
    if (request.theme.isBlank()) {
      throw LocalCgyyApiException("请填写活动主题", "invalid_request", HttpStatusCode.BadRequest)
    }
    if (request.joinerNum <= 0) {
      throw LocalCgyyApiException("参与人数必须大于 0", "invalid_request", HttpStatusCode.BadRequest)
    }
    if (request.activityContent.isBlank()) {
      throw LocalCgyyApiException("请填写活动内容", "invalid_request", HttpStatusCode.BadRequest)
    }
    if (request.joiners.isBlank()) {
      throw LocalCgyyApiException("请填写参与人说明", "invalid_request", HttpStatusCode.BadRequest)
    }
  }

  private fun mapVenueSite(raw: JsonObject): CgyyVenueSiteDto =
      CgyyVenueSiteDto(
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
              CgyySpaceAvailabilityDto(
                  spaceId = space["id"]?.jsonPrimitive?.intOrNull ?: 0,
                  spaceName = space.string("spaceName"),
                  venueSiteId = space["venueSiteId"]?.jsonPrimitive?.intOrNull ?: venueSiteId,
                  venueSpaceGroupId = space["venueSpaceGroupId"]?.jsonPrimitive?.intOrNull,
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
    return CgyySlotStatusDto(
        timeId = timeId,
        reservationStatus = reservationStatus,
        isReservable =
            reservationStatus == 1 && tradeNo == null && orderId == null && takeUp != true,
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
        purposeTypeName = purposeType?.let(::purposeTypeName),
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
            if (key !in results) {
              results[key] = name
            }
          }
          element.values.forEach(::traverse)
        }
        else -> Unit
      }
    }

    traverse(raw)
    return results.entries.map { CgyyPurposeTypeDto(it.key, it.value) }.sortedBy { it.key }
  }

  private fun fallbackPurposeTypes(): List<CgyyPurposeTypeDto> =
      listOf(
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

  private fun purposeTypeName(key: Int): String? =
      fallbackPurposeTypes().firstOrNull { it.key == key }?.name

  private fun JsonArray.toStringList(): List<String> = mapNotNull {
    it.jsonPrimitive.contentOrNull?.takeIf(String::isNotBlank)
  }

  private fun JsonObject.string(key: String): String =
      this[key]?.jsonPrimitive?.contentOrNull.orEmpty()
}

private data class LocalCgyyApiEnvelope(
    val data: JsonElement?,
    val message: String,
    val raw: JsonObject,
)

private class LocalCgyyClient(
    private val username: String,
    private val signer: LocalCgyySigner = LocalCgyySigner(),
) {
  private val json = Json { ignoreUnknownKeys = true }
  private val loginMutex = Mutex()

  private var accessToken: String? = null

  suspend fun getVenueSites(): JsonArray {
    val data =
        requestJson(
                operation = "list_sites",
                method = HttpMethod.Get,
                path = "/api/front/website/venues",
                params = mapOf("page" to -1, "size" to -1, "reservationRoleId" to 3),
            )
            .data
    return data.asVenueSiteArray()
  }

  suspend fun getPurposeTypesRaw(): JsonElement? =
      requestJson(
              operation = "list_purpose_types",
              method = HttpMethod.Get,
              path = "/api/codes",
          )
          .data

  suspend fun getReservationDayInfo(searchDate: String, venueSiteId: Int): JsonObject =
      requestJson(
              operation = "get_day_info",
              method = HttpMethod.Get,
              path = "/api/reservation/day/info",
              params = mapOf("searchDate" to searchDate, "venueSiteId" to venueSiteId),
          )
          .data
          ?.jsonObject
          ?: throw LocalCgyyApiException(
              "研讨室可用性响应为空",
              "day_info_failed",
              HttpStatusCode.BadGateway,
          )

  suspend fun createReservationOrder(
      venueSiteId: Int,
      reservationDate: String,
      weekStartDate: String,
      reservationOrderJson: String,
      token: String,
  ): LocalCgyyApiEnvelope =
      requestJson(
          operation = "create_reservation_order",
          method = HttpMethod.Post,
          path = "/api/reservation/order/info",
          form =
              mapOf(
                  "venueSiteId" to venueSiteId,
                  "reservationDate" to reservationDate,
                  "weekStartDate" to weekStartDate,
                  "reservationOrderJson" to reservationOrderJson,
                  "token" to token,
              ),
      )

  suspend fun getCaptcha(): LocalCgyyCaptchaChallenge {
    val now = localCgyyNowMillis()
    val data =
        requestJson(
                operation = "get_captcha",
                method = HttpMethod.Get,
                path = "/api/captcha/get",
                params =
                    mapOf(
                        "captchaType" to "blockPuzzle",
                        "clientUid" to "slider-$now",
                        "ts" to now,
                    ),
            )
            .data
            ?.jsonObject
            ?: throw LocalCgyyApiException("验证码响应为空", "captcha_error", HttpStatusCode.BadGateway)
    val success = data["success"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() ?: false
    if (!success) {
      throw LocalCgyyApiException(
          data["repMsg"]?.jsonPrimitive?.contentOrNull ?: "获取验证码失败",
          "captcha_error",
          HttpStatusCode.BadGateway,
      )
    }
    val repData =
        data["repData"]?.jsonObject
            ?: throw LocalCgyyApiException("验证码数据缺失", "captcha_error", HttpStatusCode.BadGateway)
    return LocalCgyyCaptchaChallenge(
        secretKey = repData.requireString("secretKey"),
        token = repData.requireString("token"),
        originalImageBase64 = repData.requireString("originalImageBase64"),
        jigsawImageBase64 = repData.requireString("jigsawImageBase64"),
    )
  }

  suspend fun verifyCaptcha(pointJson: String, token: String): JsonObject {
    val data =
        requestJson(
                operation = "verify_captcha",
                method = HttpMethod.Post,
                path = "/api/captcha/check",
                form = mapOf("pointJson" to pointJson, "token" to token),
            )
            .data
            ?.jsonObject
            ?: throw LocalCgyyApiException("验证码校验响应为空", "captcha_error", HttpStatusCode.BadGateway)
    val success = data["success"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() ?: false
    if (!success) {
      throw LocalCgyyApiException(
          data["repMsg"]?.jsonPrimitive?.contentOrNull ?: "验证码校验失败",
          "captcha_error",
          HttpStatusCode.BadGateway,
      )
    }
    return data
  }

  suspend fun submitReservationOrder(
      venueSiteId: Int,
      reservationDate: String,
      reservationOrderJson: String,
      weekStartDate: String,
      phone: String,
      theme: String,
      purposeType: Int,
      joinerNum: Int,
      activityContent: String,
      joiners: String,
      captchaVerification: String,
      token: String,
      isPhilosophySocialSciences: Int,
      isOffSchoolJoiner: Int,
  ): LocalCgyyApiEnvelope =
      requestJson(
          operation = "submit_reservation_order",
          method = HttpMethod.Post,
          path = "/api/reservation/order/submit",
          form =
              mapOf(
                  "venueSiteId" to venueSiteId,
                  "reservationDate" to reservationDate,
                  "reservationOrderJson" to reservationOrderJson,
                  "weekStartDate" to weekStartDate,
                  "phone" to phone,
                  "theme" to theme,
                  "purposeType" to purposeType,
                  "joinerNum" to joinerNum,
                  "activityContent" to activityContent,
                  "joiners" to joiners,
                  "isPhilosophySocialSciences" to isPhilosophySocialSciences,
                  "isOffSchoolJoiner" to isOffSchoolJoiner,
                  "captchaVerification" to captchaVerification,
                  "token" to token,
              ),
      )

  suspend fun getMineOrders(page: Int, size: Int): JsonObject =
      requestJson(
              operation = "list_orders",
              method = HttpMethod.Get,
              path = "/api/orders/mine",
              params = mapOf("page" to page, "size" to size),
          )
          .data
          ?.jsonObject ?: buildJsonObject {}

  suspend fun getOrderDetail(orderId: Int): JsonObject =
      requestJson(
              operation = "get_order_detail",
              method = HttpMethod.Get,
              path = "/api/orders/$orderId",
          )
          .data
          ?.jsonObject ?: buildJsonObject {}

  suspend fun cancelOrder(orderId: Int): LocalCgyyApiEnvelope =
      requestJson(
          operation = "cancel_order",
          method = HttpMethod.Post,
          path = "/api/orders/new/cancel/$orderId",
      )

  suspend fun getLockCode(): JsonElement? =
      requestJson(
              operation = "get_lock_code",
              method = HttpMethod.Get,
              path = "/api/orders/lock/code",
          )
          .data

  private suspend fun requestJson(
      operation: String,
      method: HttpMethod,
      path: String,
      params: Map<String, Any?> = emptyMap(),
      form: Map<String, Any?> = emptyMap(),
      extraHeaders: Map<String, String> = emptyMap(),
      includeAuthorization: Boolean = true,
      allowRetry: Boolean = true,
  ): LocalCgyyApiEnvelope {
    if (includeAuthorization) {
      ensureBusinessLogin()
    }

    val timestamp = localCgyyNowMillis()
    val pathOnly = normalizePath(path)
    val requestParams =
        if (method == HttpMethod.Get) signer.addNoCacheIfMissing(params, timestamp) else params
    val signSource = if (method == HttpMethod.Get) requestParams else form
    val sign = signer.sign(pathOnly, signSource, timestamp)

    val response =
        LocalUpstreamClientProvider.shared().request(buildUrl(pathOnly)) {
          this.method = method
          header(HttpHeaders.Accept, "application/json, text/plain, */*")
          header(
              HttpHeaders.Referrer,
              localUpstreamUrl("https://cgyy.buaa.edu.cn/venue-zhjs/mobileReservation"),
          )
          header("app-key", signer.appKey)
          header("timestamp", timestamp.toString())
          header("sign", sign)
          if (includeAuthorization) {
            header("cgAuthorization", requireNotNull(accessToken) { "CGYY access token missing" })
          }
          extraHeaders.forEach { (key, value) -> header(key, value) }

          requestParams.forEach { (key, value) ->
            if (method == HttpMethod.Get && value != null) {
              parameter(key, value.toString())
            }
          }
          if (method != HttpMethod.Get) {
            val parameters =
                Parameters.build {
                  form.forEach { (key, value) -> if (value != null) append(key, value.toString()) }
                }
            setBody(FormDataContent(parameters))
          }
        }

    val body = response.bodyAsText()
    if (isLoginRedirect(response, body)) {
      accessToken = null
      if (!allowRetry) {
        throw LocalCgyyApiException("研讨室系统登录状态失效", "unauthenticated", HttpStatusCode.Unauthorized)
      }
      ensureBusinessLogin(forceRefresh = true)
      return requestJson(
          operation = operation,
          method = method,
          path = path,
          params = params,
          form = form,
          extraHeaders = extraHeaders,
          includeAuthorization = includeAuthorization,
          allowRetry = false,
      )
    }

    val raw =
        runCatching { json.parseToJsonElement(body).jsonObject }
            .getOrElse {
              throw LocalCgyyApiException(
                  "研讨室系统返回了非 JSON 响应",
                  "cgyy_error",
                  HttpStatusCode.BadGateway,
              )
            }
    val code = raw["code"]?.jsonPrimitive?.intOrNull
    if (code != 200) {
      throw LocalCgyyApiException(
          raw["message"]?.jsonPrimitive?.contentOrNull ?: "研讨室系统请求失败",
          "cgyy_error",
          HttpStatusCode.BadGateway,
      )
    }
    return LocalCgyyApiEnvelope(
        data = raw["data"],
        message = raw["message"]?.jsonPrimitive?.contentOrNull ?: "OK",
        raw = raw,
    )
  }

  private suspend fun ensureBusinessLogin(forceRefresh: Boolean = false) {
    LocalAuthSessionStore.get()
        ?: throw LocalCgyyApiException("登录状态已失效", "unauthenticated", HttpStatusCode.Unauthorized)
    if (!forceRefresh && !accessToken.isNullOrBlank()) return

    loginMutex.withLock {
      if (!forceRefresh && !accessToken.isNullOrBlank()) return@withLock
      accessToken = null

      val manageLoginResponse =
          LocalUpstreamClientProvider.shared().get(localUpstreamUrl("${BASE_URL}sso/manageLogin"))
      val manageLoginBody = runCatching { manageLoginResponse.bodyAsText() }.getOrDefault("")
      if (isLoginRedirect(manageLoginResponse, manageLoginBody)) {
        throw LocalCgyyApiException("未获取到研讨室登录态", "unauthenticated", HttpStatusCode.Unauthorized)
      }

      val cookieFromResponse =
          manageLoginResponse.headers
              .getAll(HttpHeaders.SetCookie)
              .orEmpty()
              .firstNotNullOfOrNull { header ->
                header
                    .substringBefore(';')
                    .split('=', limit = 2)
                    .takeIf { it.size == 2 }
                    ?.takeIf { it[0].trim() == SSO_COOKIE_NAME }
                    ?.get(1)
                    ?.trim()
                    ?.takeIf { it.isNotBlank() }
              }
      val storage =
          LocalCookieStore.storage(
              ConnectionRuntime.currentMode()?.takeIf { it != ConnectionMode.SERVER_RELAY }
                  ?: ConnectionMode.DIRECT
          )
      val ssoToken =
          cookieFromResponse
              ?: storage
                  .get(Url(localUpstreamUrl(BASE_URL)))
                  .firstOrNull { it.name == SSO_COOKIE_NAME }
                  ?.value
                  ?.takeIf { it.isNotBlank() }
              ?: throw LocalCgyyApiException(
                  "未获取到研讨室 SSO Token",
                  "unauthenticated",
                  HttpStatusCode.Unauthorized,
              )

      val loginResponse =
          requestJson(
              operation = "business_login",
              method = HttpMethod.Post,
              path = "/api/login",
              extraHeaders = mapOf("Sso-Token" to ssoToken),
              includeAuthorization = false,
              allowRetry = false,
          )
      accessToken =
          loginResponse.data
              ?.jsonObject
              ?.get("token")
              ?.jsonObject
              ?.get("access_token")
              ?.jsonPrimitive
              ?.contentOrNull
              ?: throw LocalCgyyApiException(
                  "研讨室登录成功但未返回 access_token",
                  "unauthenticated",
                  HttpStatusCode.Unauthorized,
              )
    }
  }

  private fun isLoginRedirect(response: HttpResponse, body: String): Boolean {
    val finalUrl = response.call.request.url.toString()
    if (response.status == HttpStatusCode.Unauthorized) return true
    if (localIsSsoUrl(finalUrl)) return true
    return body.contains("name=\"execution\"") && body.contains("username_password")
  }

  private fun buildUrl(path: String): String =
      localUpstreamUrl("$BASE_URL${path.removePrefix("/")}")

  private fun normalizePath(path: String): String = if (path.startsWith("/")) path else "/$path"

  private fun JsonObject.requireString(key: String): String =
      this[key]?.jsonPrimitive?.contentOrNull
          ?: throw LocalCgyyApiException("响应缺少字段: $key", "cgyy_error", HttpStatusCode.BadGateway)

  private fun JsonElement?.asVenueSiteArray(): JsonArray {
    val content =
        when (this) {
          null -> emptyList()
          is JsonObject -> this["content"]?.jsonArray.orEmpty()
          is JsonArray -> this
          else -> emptyList()
        }
    return JsonArray(
        content.flatMap { venueElement ->
          val venue = venueElement.jsonObject
          val venueId = venue["id"]?.jsonPrimitive?.intOrNull ?: return@flatMap emptyList()
          val venueName = venue["venueName"]?.jsonPrimitive?.contentOrNull.orEmpty()
          val campusName = venue["campusName"]?.jsonPrimitive?.contentOrNull.orEmpty()
          venue["siteList"]
              ?.jsonArray
              ?.mapNotNull { siteElement ->
                val site = siteElement.jsonObject
                val siteId =
                    site["id"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
                        ?: return@mapNotNull null
                buildJsonObject {
                  put("id", kotlinx.serialization.json.JsonPrimitive(siteId))
                  put("venueId", kotlinx.serialization.json.JsonPrimitive(venueId))
                  put(
                      "siteName",
                      kotlinx.serialization.json.JsonPrimitive(
                          site["siteName"]?.jsonPrimitive?.contentOrNull.orEmpty()
                      ),
                  )
                  put("venueName", kotlinx.serialization.json.JsonPrimitive(venueName))
                  put("campusName", kotlinx.serialization.json.JsonPrimitive(campusName))
                }
              }
              .orEmpty()
        }
    )
  }

  companion object {
    private const val BASE_URL = "https://cgyy.buaa.edu.cn/venue-zhjs-server/"
    private const val SSO_COOKIE_NAME = "sso_buaa_zhjs_token"
  }
}

internal class LocalCgyyApiException(
    rawMessage: String,
    val code: String,
    val status: HttpStatusCode,
) : Exception(rawMessage)

private fun localCgyyNowMillis(): Long = Clock.System.now().toEpochMilliseconds()
