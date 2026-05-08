package cn.edu.ubaa.api.local

import cn.edu.ubaa.api.auth.ApiCallException
import cn.edu.ubaa.api.auth.toUserFacingApiException
import cn.edu.ubaa.api.auth.userFacingMessageForCode
import cn.edu.ubaa.api.feature.LibBookApiBackend
import cn.edu.ubaa.model.dto.LibBookAreaDetailDto
import cn.edu.ubaa.model.dto.LibBookAreaDto
import cn.edu.ubaa.model.dto.LibBookBookingDto
import cn.edu.ubaa.model.dto.LibBookBookingsResponse
import cn.edu.ubaa.model.dto.LibBookCancelResponse
import cn.edu.ubaa.model.dto.LibBookLibraryDto
import cn.edu.ubaa.model.dto.LibBookReserveRequest
import cn.edu.ubaa.model.dto.LibBookReserveResponse
import cn.edu.ubaa.model.dto.LibBookSeatDto
import cn.edu.ubaa.model.dto.LibBookStoreyDto
import cn.edu.ubaa.model.dto.LibBookTimeSlotDto
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.http.contentType
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

internal class LocalLibBookApiBackend : LibBookApiBackend {
  private val clientMutex = Mutex()
  private val clientCache = mutableMapOf<String, LocalLibBookClient>()

  internal fun clearCache() {
    clientCache.clear()
  }

  override suspend fun getLibraries(day: String): Result<List<LibBookLibraryDto>> =
      execute("图书馆楼馆列表加载失败，请稍后重试") { client -> client.getLibraries(day).map(::mapLibrary) }

  override suspend fun getAreas(
      premisesId: String,
      storeyId: String?,
      day: String,
  ): Result<List<LibBookAreaDto>> =
      execute("图书馆分区列表加载失败，请稍后重试") { client ->
        client.getAreas(premisesId, storeyId, day).map(::mapArea)
      }

  override suspend fun getAreaDetail(areaId: String): Result<LibBookAreaDetailDto> =
      execute("图书馆分区信息加载失败，请稍后重试") { client -> mapAreaDetail(areaId, client.getAreaInfo(areaId)) }

  override suspend fun getSeats(
      areaId: String,
      day: String,
      startTime: String,
      endTime: String,
  ): Result<List<LibBookSeatDto>> =
      execute("图书馆座位列表加载失败，请稍后重试") { client ->
        client.getSeats(areaId, day, startTime, endTime).map(::mapSeat).sortedBy { it.no }
      }

  override suspend fun reserve(request: LibBookReserveRequest): Result<LibBookReserveResponse> =
      execute("图书馆座位预约失败，请稍后重试") { client ->
        val seatId =
            request.seatId.takeIf { it.isNotBlank() }
                ?: throw LocalLibBookApiException(
                    "请选择座位",
                    "invalid_request",
                    HttpStatusCode.BadRequest,
                )
        if (request.segment.isBlank() || request.day.isBlank()) {
          throw LocalLibBookApiException(
              "预约时间段无效，请刷新后重试",
              "invalid_request",
              HttpStatusCode.BadRequest,
          )
        }
        val response = client.reserve(request.copy(seatId = seatId))
        val message =
            response.string("message").ifBlank { response.string("msg").ifBlank { "预约成功" } }
        LibBookReserveResponse(
            success = response.isBusinessSuccess(),
            message = message,
            booking =
                response["data"]?.jsonObjectOrNull()?.let { data ->
                  data["bookInfo"]?.jsonObjectOrNull()?.let(::mapBooking)
                      ?: data["booking"]?.jsonObjectOrNull()?.let(::mapBooking)
                },
        )
      }

  override suspend fun getBookings(page: Int, limit: Int): Result<LibBookBookingsResponse> =
      execute("图书馆预约列表加载失败，请稍后重试") { client ->
        val raw = client.getBookings(page, limit)
        val data = raw["data"]?.jsonObjectOrNull()
        val bookings =
            data?.get("data")?.jsonArrayOrNull()?.map(::mapBooking)
                ?: data?.get("list")?.jsonArrayOrNull()?.map(::mapBooking)
                ?: emptyList()
        LibBookBookingsResponse(
            bookings = bookings,
            page = data?.int("current_page") ?: data?.int("page") ?: page,
            limit = data?.int("per_page") ?: data?.int("limit") ?: limit,
            total = data?.int("total") ?: bookings.size,
        )
      }

  override suspend fun cancelBooking(bookingId: String): Result<LibBookCancelResponse> =
      execute("图书馆预约取消失败，请稍后重试") { client ->
        if (bookingId.isBlank()) {
          throw LocalLibBookApiException(
              "预约记录不存在或已失效",
              "libbook_not_found",
              HttpStatusCode.NotFound,
          )
        }
        val response = client.cancelBooking(bookingId)
        val message =
            response.string("message").ifBlank { response.string("msg").ifBlank { "取消成功" } }
        if (!response.isBusinessSuccess()) {
          val errorCode = response.messageToLibBookErrorCode()
          throw LocalLibBookApiException(message, errorCode, errorCode.toLibBookHttpStatus())
        }
        LibBookCancelResponse(
            success = response.isBusinessSuccess(),
            message = message,
        )
      }

  private suspend fun currentClient(username: String): LocalLibBookClient =
      clientMutex.withLock { clientCache.getOrPut(username) { LocalLibBookClient() } }

  private suspend fun <T> execute(
      defaultMessage: String,
      block: suspend (LocalLibBookClient) -> T,
  ): Result<T> {
    val session =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val username = session.user.schoolid.ifBlank { session.username }
    if (username.isBlank()) return Result.failure(localUnauthenticatedApiException())

    return try {
      Result.success(block(currentClient(username)))
    } catch (error: Exception) {
      Result.failure(mapFailure(error, defaultMessage))
    }
  }

  private suspend fun mapFailure(error: Exception, defaultMessage: String): Exception =
      when (error) {
        is LocalLibBookApiException ->
            if (error.code == "unauthenticated" || error.code == "libbook_auth_failed") {
              resolveLocalBusinessAuthenticationFailure("libbook_auth_failed")
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
}

private class LocalLibBookClient(
    private val httpClient: HttpClient = LocalUpstreamClientProvider.libBookShared(),
) {
  private val json = Json { ignoreUnknownKeys = true }
  private val loginMutex = Mutex()
  private var token: String? = null

  suspend fun getLibraries(day: String): JsonArray =
      requestJson("list_libraries", "space/pcTopFor", buildJsonObject { put("day", day) })
          .dataList("list")

  suspend fun getAreas(premisesId: String, storeyId: String?, day: String): JsonArray =
      requestJson(
              operation = "list_areas",
              path = "space/pick",
              body =
                  buildJsonObject {
                    put("premisesIds", premisesId)
                    putJsonArray("categoryIds") {}
                    putJsonArray("storeyIds") {
                      if (!storeyId.isNullOrBlank()) add(JsonPrimitive(storeyId))
                    }
                    putJsonArray("boutiqueIds") {}
                    put("date", day)
                  },
          )
          .dataList("area")

  suspend fun getAreaInfo(areaId: String): JsonObject =
      requestJson("get_area_info", "Space/map", buildJsonObject { put("id", areaId) }).raw

  suspend fun getSeats(
      areaId: String,
      day: String,
      startTime: String,
      endTime: String,
  ): JsonArray =
      requestJson(
              operation = "list_seats",
              path = "Space/seat",
              body =
                  buildJsonObject {
                    put("id", areaId)
                    put("day", day)
                    putJsonArray("label_id") {}
                    put("start_time", startTime)
                    put("end_time", endTime)
                    put("begdate", "")
                    put("enddate", "")
                  },
          )
          .dataList("list")

  suspend fun reserve(request: LibBookReserveRequest): JsonObject =
      requestJson(
              operation = "reserve",
              path = "space/confirm",
              body =
                  buildJsonObject {
                    put("aesjson", LocalLibBookCrypto.encryptReserveRequest(request))
                  },
          )
          .raw

  suspend fun getBookings(page: Int, limit: Int): JsonObject =
      requestJson(
              operation = "list_bookings",
              path = "member/seat",
              body =
                  buildJsonObject {
                    put("type", "1")
                    put("page", page)
                    put("limit", limit)
                  },
          )
          .raw

  suspend fun cancelBooking(bookingId: String): JsonObject =
      requestJson("cancel_booking", "space/cancel", buildJsonObject { put("id", bookingId) }).raw

  private suspend fun requestJson(
      operation: String,
      path: String,
      body: JsonObject,
      includeAuthorization: Boolean = true,
      allowRetry: Boolean = true,
  ): LocalLibBookEnvelope {
    if (includeAuthorization) ensureLogin()
    val response =
        httpClient.post(localUpstreamUrl("$BASE_URL/v4/${path.removePrefix("/")}")) {
          applyHeaders()
          if (includeAuthorization) {
            header(HttpHeaders.Authorization, "bearer${requireNotNull(token)}")
          }
          contentType(ContentType.Application.Json)
          setBody(body)
        }
    val raw = parseJsonObject(response, "libbook_error")
    if (isLoginExpired(raw)) {
      token = null
      if (!allowRetry) {
        throw LocalLibBookApiException(
            "图书馆登录状态失效",
            "libbook_auth_failed",
            HttpStatusCode.Unauthorized,
        )
      }
      ensureLogin(forceRefresh = true)
      return requestJson(operation, path, body, includeAuthorization, allowRetry = false)
    }
    val code = raw["code"]?.jsonPrimitive?.intOrNull
    if (code != null && code !in setOf(0, 1)) {
      val errorCode = raw.messageToLibBookErrorCode()
      throw LocalLibBookApiException(
          raw.string("message").ifBlank { raw.string("msg").ifBlank { "图书馆接口请求失败" } },
          errorCode,
          errorCode.toLibBookHttpStatus(),
      )
    }
    return LocalLibBookEnvelope(raw["data"], raw)
  }

  private suspend fun ensureLogin(forceRefresh: Boolean = false) {
    LocalAuthSessionStore.get()
        ?: throw LocalLibBookApiException("登录状态已失效", "unauthenticated", HttpStatusCode.Unauthorized)
    if (!forceRefresh && !token.isNullOrBlank()) return

    loginMutex.withLock {
      if (!forceRefresh && !token.isNullOrBlank()) return@withLock
      token = null

      val cas = fetchCasToken()
      val response =
          requestJson(
              operation = "login",
              path = "login/user",
              body = buildJsonObject { put("cas", cas) },
              includeAuthorization = false,
              allowRetry = false,
          )
      val member = response.raw["data"]?.jsonObjectOrNull()?.get("member")?.jsonObjectOrNull()
      token =
          member?.string("token")?.takeIf { it.isNotBlank() }
              ?: throw LocalLibBookApiException(
                  "图书馆登录成功但未返回 token",
                  "libbook_auth_failed",
                  HttpStatusCode.Unauthorized,
              )
    }
  }

  private suspend fun fetchCasToken(): String {
    val client = LocalUpstreamClientProvider.newLibBookNoRedirectClient()
    try {
      var currentUrl = localUpstreamUrl(CAS_LOGIN_URL)
      repeat(8) {
        val response = client.get(currentUrl) { applyHeaders() }
        extractCasToken(response.call.request.url.toString())?.let {
          return it
        }
        extractCasToken(response.headers[HttpHeaders.Location])?.let {
          return it
        }
        val location =
            response.headers[HttpHeaders.Location]
                ?: throw LocalLibBookApiException(
                    "图书馆 CAS 登录跳转缺少 Location",
                    "libbook_auth_failed",
                    HttpStatusCode.Unauthorized,
                )
        currentUrl = resolveRedirectUrl(response.call.request.url.toString(), location)
      }
      throw LocalLibBookApiException(
          "未能获取图书馆 CAS 参数",
          "libbook_auth_failed",
          HttpStatusCode.Unauthorized,
      )
    } finally {
      client.close()
    }
  }

  private fun io.ktor.client.request.HttpRequestBuilder.applyHeaders() {
    header(HttpHeaders.Accept, "application/json, text/plain, */*")
    header(HttpHeaders.UserAgent, USER_AGENT)
    header("X-Requested-With", "XMLHttpRequest")
    header(HttpHeaders.Referrer, localUpstreamUrl(BASE_URL))
    header(HttpHeaders.Origin, localUpstreamUrl(BASE_URL))
  }

  private suspend fun parseJsonObject(response: HttpResponse, code: String): JsonObject {
    if (response.status != HttpStatusCode.OK) {
      throw LocalLibBookApiException("图书馆接口响应异常", code, response.status)
    }
    val body = response.bodyAsText()
    return runCatching { json.parseToJsonElement(body).jsonObject }
        .getOrElse {
          throw LocalLibBookApiException("图书馆接口返回了非 JSON 响应", code, HttpStatusCode.BadGateway)
        }
  }

  private fun isLoginExpired(raw: JsonObject): Boolean {
    val message = raw.string("message").ifBlank { raw.string("msg") }
    return message.contains("登录失效") || message.contains("请重新登录") || message.contains("未登录")
  }

  private fun extractCasToken(url: String?): String? {
    if (url.isNullOrBlank()) return null
    val decoded = LocalWebVpnSupport.fromWebVpnUrl(url)
    return listOf(decoded, url)
        .firstNotNullOfOrNull { candidate ->
          val query = runCatching { Url(candidate).parameters }.getOrNull()
          query?.get("cas")?.takeIf { it.isNotBlank() }
              ?: CAS_TOKEN_REGEX.find(candidate)?.groupValues?.getOrNull(1)
        }
        ?.takeIf { it.isNotBlank() }
  }

  private fun resolveRedirectUrl(baseUrl: String, location: String): String {
    if (location.startsWith("http://") || location.startsWith("https://")) {
      return localUpstreamUrl(LocalWebVpnSupport.fromWebVpnUrl(location))
    }
    val base = Url(baseUrl)
    val prefix =
        "${base.protocol.name}://${base.host}${base.port.takeIf { it > 0 }?.let { ":$it" }.orEmpty()}"
    return "$prefix${if (location.startsWith("/")) location else "/$location"}"
  }

  companion object {
    private const val BASE_URL = "https://booking.lib.buaa.edu.cn"
    private const val CAS_LOGIN_URL =
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbooking.lib.buaa.edu.cn%2Fv4%2Flogin%2Fcas"
    private const val USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36"
    private val CAS_TOKEN_REGEX = Regex("""[?&#]cas=([^&#]+)""")
  }
}

private data class LocalLibBookEnvelope(val data: JsonElement?, val raw: JsonObject)

private class LocalLibBookApiException(
    rawMessage: String,
    val code: String,
    val status: HttpStatusCode,
) : Exception(rawMessage)

private fun LocalLibBookEnvelope.dataList(key: String): JsonArray =
    data?.jsonObjectOrNull()?.get(key)?.jsonArrayOrNull() ?: buildJsonArray {}

private fun mapLibrary(element: JsonElement): LibBookLibraryDto {
  val raw = element.jsonObject
  return LibBookLibraryDto(
      id = raw.string("id"),
      name = raw.string("name"),
      freeNum = raw.int("free_num"),
      totalNum = raw.int("total_num"),
      storeys = raw["children"]?.jsonArrayOrNull()?.map(::mapStorey).orEmpty(),
  )
}

private fun mapStorey(element: JsonElement): LibBookStoreyDto {
  val raw = element.jsonObject
  return LibBookStoreyDto(
      id = raw.string("id"),
      name = raw.string("name"),
      freeNum = raw.int("free_num"),
      totalNum = raw.int("total_num"),
  )
}

private fun mapArea(element: JsonElement): LibBookAreaDto {
  val raw = element.jsonObject
  return LibBookAreaDto(
      id = raw.string("id"),
      name = raw.string("name"),
      areaName = raw.string("area"),
      premisesId = raw.string("premises_id").ifBlank { raw.string("premisesId") },
      storeyId = raw.string("storey_id").ifBlank { raw.string("storeyId") },
      freeNum = raw.int("free_num"),
      totalNum = raw.int("total_num"),
  )
}

private fun mapAreaDetail(areaId: String, raw: JsonObject): LibBookAreaDetailDto {
  val data = raw["data"]?.jsonObjectOrNull()
  val area = data?.get("area")?.jsonObjectOrNull()
  val dateList = data?.get("date")?.jsonObjectOrNull()?.get("list")?.jsonArrayOrNull().orEmpty()
  val availableDates =
      dateList.mapNotNull { date ->
        val item = date.jsonObject
        item.string("day").ifBlank { item.string("date") }.takeIf { it.isNotBlank() }
      }
  val timeSlots =
      dateList
          .firstOrNull()
          ?.jsonObject
          ?.get("times")
          ?.jsonArrayOrNull()
          ?.mapNotNull { element ->
            val item = element.jsonObject
            val id = item.string("id").takeIf { it.isNotBlank() } ?: return@mapNotNull null
            val start = item.string("start")
            val end = item.string("end")
            LibBookTimeSlotDto(id = id, start = start, end = end)
          }
          .orEmpty()
  return LibBookAreaDetailDto(
      id = area?.string("id").orEmpty().ifBlank { areaId },
      name = area?.string("name").orEmpty(),
      availableDates = availableDates,
      timeSlots = timeSlots,
  )
}

private fun mapSeat(element: JsonElement): LibBookSeatDto {
  val raw = element.jsonObject
  val status = raw.string("status")
  return LibBookSeatDto(
      id = raw.string("id"),
      name = raw.string("name"),
      no = raw.string("no"),
      status = status,
      statusName = raw.string("status_name"),
      isAvailable = status == "1",
  )
}

private fun mapBooking(element: JsonElement): LibBookBookingDto {
  val raw = element.jsonObject
  return LibBookBookingDto(
      id = raw.string("id"),
      nameMerge = raw.string("nameMerge").ifBlank { raw.string("name_merge") },
      areaName = raw.string("name").ifBlank { raw.string("area_name") },
      seatNo = raw.string("no").ifBlank { raw.string("seat_no") },
      day = raw.string("day").ifBlank { raw.string("date") },
      beginTime = raw.string("beginTime").ifBlank { raw.string("begin_time") },
      endTime = raw.string("endTime").ifBlank { raw.string("end_time") },
      status = raw.string("status"),
      statusName = raw.string("status_name"),
  )
}

private fun JsonObject.isBusinessSuccess(): Boolean {
  val code = this["code"]?.jsonPrimitive?.intOrNull
  if (code != null && code !in setOf(0, 1)) return false
  val message = string("message").ifBlank { string("msg") }
  return !message.contains("失败") &&
      !message.contains("不可") &&
      !message.contains("已被") &&
      !message.contains("不能取消") &&
      !message.contains("无法取消") &&
      !message.contains("已取消") &&
      !message.contains("用户取消") &&
      !message.contains("已结束") &&
      !message.contains("已完成")
}

private fun JsonObject.messageToLibBookErrorCode(): String {
  val message = string("message").ifBlank { string("msg") }
  return when {
    message.contains("已取消") ||
        message.contains("用户取消") ||
        message.contains("已结束") ||
        message.contains("不能取消") ||
        message.contains("无法取消") ||
        message.contains("已完成") ||
        message.contains("不存在") ||
        message.contains("失效") -> "libbook_not_found"
    message.contains("已被") || message.contains("不可") || message.contains("无可预约") ->
        "libbook_seat_unavailable"
    else -> "libbook_error"
  }
}

private fun String.toLibBookHttpStatus(): HttpStatusCode =
    when (this) {
      "libbook_not_found" -> HttpStatusCode.NotFound
      "libbook_seat_unavailable" -> HttpStatusCode.Conflict
      "invalid_request" -> HttpStatusCode.BadRequest
      else -> HttpStatusCode.BadGateway
    }

private fun JsonElement.jsonObjectOrNull(): JsonObject? = this as? JsonObject

private fun JsonElement.jsonArrayOrNull(): JsonArray? = this as? JsonArray

private fun JsonObject.string(key: String): String =
    this[key]?.jsonPrimitive?.contentOrNull.orEmpty()

private fun JsonObject.int(key: String): Int =
    this[key]?.jsonPrimitive?.intOrNull
        ?: this[key]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
        ?: 0
