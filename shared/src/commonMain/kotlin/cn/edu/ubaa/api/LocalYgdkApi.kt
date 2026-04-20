package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.YgdkClockinSubmitRequest
import cn.edu.ubaa.model.dto.YgdkClockinSubmitResponse
import cn.edu.ubaa.model.dto.YgdkItemDto
import cn.edu.ubaa.model.dto.YgdkOverviewResponse
import cn.edu.ubaa.model.dto.YgdkPhotoUpload
import cn.edu.ubaa.model.dto.YgdkRecordDto
import cn.edu.ubaa.model.dto.YgdkRecordsPageResponse
import cn.edu.ubaa.model.dto.YgdkTermSummaryDto
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.forms.MultiPartFormDataContent
import io.ktor.client.request.forms.formData
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentDisposition
import io.ktor.http.ContentType
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Parameters
import io.ktor.http.Url
import io.ktor.http.decodeURLQueryComponent
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.time.Clock
import kotlin.time.Duration.Companion.hours
import kotlin.time.Instant
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toInstant
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

internal class LocalYgdkApiBackend : YgdkApiBackend {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun getOverview(): Result<YgdkOverviewResponse> =
      runLocalYgdkCall("阳光打卡概览加载失败，请稍后重试") { studentId ->
        val session = createLocalYgdkSession(studentId)
        val classify = resolveSportsClassify(fetchClassifyList(session))
        val items = fetchItemList(session, classify.classifyId)
        val defaultItem = resolveDefaultItem(items)
        val count = runCatching { fetchCheckCount(session, classify.classifyId) }.getOrNull()
        val term = runCatching { fetchTerm(session) }.getOrNull()

        YgdkOverviewResponse(
            summary = mapYgdkSummary(classify, count, term),
            classifyId = classify.classifyId,
            classifyName = classify.name,
            defaultItemId = defaultItem.itemId,
            defaultItemName = defaultItem.name,
            items = items.map { it.toDto() },
        )
      }

  override suspend fun getRecords(page: Int, size: Int): Result<YgdkRecordsPageResponse> =
      runLocalYgdkCall("阳光打卡记录加载失败，请稍后重试") { studentId ->
        if (page <= 0 || size <= 0) {
          throw ApiCallException(
              "分页参数无效",
              status = HttpStatusCode.BadRequest,
              code = "invalid_request",
          )
        }

        val session = createLocalYgdkSession(studentId)
        val classify = resolveSportsClassify(fetchClassifyList(session))
        val items = fetchItemList(session, classify.classifyId)
        val itemMap = items.associateBy { it.itemId }
        val records = fetchRecords(session, classify.classifyId, page, size)

        YgdkRecordsPageResponse(
            content = records.records.map { it.toDto(itemMap) },
            total = records.total,
            page = page,
            size = size,
            hasMore = page * size < records.total,
        )
      }

  override suspend fun submitClockin(
      request: YgdkClockinSubmitRequest
  ): Result<YgdkClockinSubmitResponse> =
      runLocalYgdkCall("阳光打卡提交失败，请稍后重试") { studentId ->
        val session = createLocalYgdkSession(studentId)
        val classify = resolveSportsClassify(fetchClassifyList(session))
        val items = fetchItemList(session, classify.classifyId)
        val selectedItem =
            request.itemId?.let { itemId ->
              items.firstOrNull { it.itemId == itemId }
                  ?: throw ApiCallException(
                      "所选运动项目不存在",
                      status = HttpStatusCode.BadRequest,
                      code = "invalid_request",
                  )
            } ?: resolveDefaultItem(items)

        val (startAt, endAt) = resolveClockinTimeRange(request.startTime, request.endTime)
        val upload =
            request.photo
                ?: YgdkPhotoUpload(defaultTransparentPhotoBytes(), "ygdk_auto.png", "image/png")
        val uploadedFileName = uploadPhoto(session, upload)
        val result =
            clockin(
                session = session,
                classifyId = classify.classifyId,
                item = selectedItem,
                startAt = startAt,
                endAt = endAt,
                place =
                    request.place?.trim().takeUnless { it.isNullOrBlank() } ?: DEFAULT_YGDK_PLACE,
                imageName = uploadedFileName,
                isOpen = request.shareToSquare ?: false,
            )

        YgdkClockinSubmitResponse(
            success = true,
            message = "打卡成功",
            recordId = result.recordId,
            summary = mapClockinSummary(classify, result),
        )
      }

  private suspend fun <T> runLocalYgdkCall(
      defaultMessage: String,
      block: suspend (String) -> T,
  ): Result<T> {
    val authSession =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())
    val studentId = authSession.user.schoolid.ifBlank { authSession.username }
    return try {
      Result.success(block(studentId))
    } catch (e: LocalYgdkAuthenticationException) {
      clearLocalConnectionSession()
      Result.failure(localUnauthenticatedApiException())
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException(defaultMessage))
    }
  }

  private suspend fun createLocalYgdkSession(studentId: String): LocalYgdkSession {
    val code = fetchOauthCode()
    val response =
        LocalUpstreamClientProvider.shared().get(
            localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin")
        ) {
          parameter("code", code)
        }
    val result = unwrapYgdkResponse(response.bodyAsText())
    val data = result.jsonObject["data"]?.jsonObject ?: result.jsonObject
    val uid = data.int("uid") ?: throw LocalYgdkAuthenticationException("阳光打卡返回 uid 缺失")
    val token =
        data.string("token")?.decodeURLQueryComponent()
            ?: throw LocalYgdkAuthenticationException("阳光打卡返回 token 缺失")
    return LocalYgdkSession(studentId = studentId, uid = uid, token = token)
  }

  private suspend fun fetchOauthCode(): String {
    val noRedirectClient = LocalUpstreamClientProvider.newNoRedirectClient()
    return try {
      var currentUrl = localYgdkOauthUrl()
      repeat(10) {
        val response = noRedirectClient.get(currentUrl)
        extractOauthCode(response.call.request.url.toString())?.let {
          return it
        }
        val location = response.headers[HttpHeaders.Location] ?: return@repeat
        val nextUrl = resolveRedirectUrl(response.call.request.url, location)
        extractOauthCode(nextUrl)?.let {
          return it
        }
        currentUrl = nextUrl
      }
      throw LocalYgdkAuthenticationException("无法获取阳光打卡登录 code，请重新登录 UBAA")
    } finally {
      noRedirectClient.close()
    }
  }

  private suspend fun fetchClassifyList(session: LocalYgdkSession): List<LocalYgdkClassifyRaw> {
    val result =
        postForm(
            session,
            localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Clockin/Classify/getList"),
        )
    val list = result.jsonObject["list"]?.jsonArray.orEmpty()
    return list.mapNotNull { element ->
      val payload = element as? JsonObject ?: return@mapNotNull null
      val classifyId = payload.int("classify_id") ?: return@mapNotNull null
      val name = payload.string("name") ?: return@mapNotNull null
      LocalYgdkClassifyRaw(
          classifyId = classifyId,
          name = name,
          termNum = payload.int("term_num"),
          monthNum = payload.int("month_num"),
          weekNum = payload.int("week_num"),
      )
    }
  }

  private suspend fun fetchItemList(
      session: LocalYgdkSession,
      classifyId: Int,
  ): List<LocalYgdkItemRaw> {
    val parameters =
        Parameters.build {
          append("page", "1")
          append("limit", "1000")
          append("classify_id", classifyId.toString())
        }
    val result =
        postForm(
            session = session,
            url = localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Clockin/Item/getList"),
            queryParameters = parameters,
            formParameters = parameters,
        )
    val list = result.jsonObject["list"]?.jsonArray.orEmpty()
    return list.mapNotNull { element ->
      val payload = element as? JsonObject ?: return@mapNotNull null
      val itemId = payload.int("item_id") ?: return@mapNotNull null
      val name = payload.string("name") ?: return@mapNotNull null
      LocalYgdkItemRaw(
          itemId = itemId,
          name = name,
          type = payload.int("type"),
          sort = payload.int("sort"),
      )
    }
  }

  private suspend fun fetchCheckCount(
      session: LocalYgdkSession,
      classifyId: Int,
  ): LocalYgdkCountRaw {
    val result =
        postForm(
            session = session,
            url = localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/getCount"),
            formParameters =
                Parameters.build {
                  append("classify_id", classifyId.toString())
                  append("user_id", session.uid.toString())
                },
        )
    val payload = result.jsonObject
    return LocalYgdkCountRaw(
        termCount = payload.int("term_count"),
        termCountShow = payload.int("term_count_show"),
        termGoodCount = payload.int("term_good_count"),
        termGoodCountShow = payload.int("term_good_count_show"),
        weekCount = payload.int("week_count"),
        weekNum = payload.int("week_num"),
        monthCount = payload.int("month_count"),
        monthNum = payload.int("month_num"),
        dayCount = payload.int("day_count"),
        termNum = payload.int("term_num"),
    )
  }

  private suspend fun fetchTerm(session: LocalYgdkSession): LocalYgdkTermRaw {
    val payload =
        postForm(session, localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Clockin/Term/get"))
            .jsonObject
    return LocalYgdkTermRaw(
        termId = payload.int("term_id"),
        id = payload.int("id"),
        name = payload.string("name"),
    )
  }

  private suspend fun fetchRecords(
      session: LocalYgdkSession,
      classifyId: Int,
      page: Int,
      size: Int,
  ): LocalYgdkRecordsPageRaw {
    val parameters =
        Parameters.build {
          append("page", page.toString())
          append("limit", size.toString())
          append("classify_id", classifyId.toString())
          append("user_id", session.uid.toString())
        }
    val payload =
        postForm(
                session = session,
                url =
                    localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/getList"),
                queryParameters = parameters,
                formParameters = parameters,
            )
            .jsonObject
    return LocalYgdkRecordsPageRaw(
        records =
            payload["list"]?.jsonArray.orEmpty().mapNotNull { element ->
              val record = element as? JsonObject ?: return@mapNotNull null
              val recordId = record.int("record_id") ?: return@mapNotNull null
              LocalYgdkRecordRaw(
                  recordId = recordId,
                  itemId = record.int("item_id"),
                  itemName = record.string("item_name"),
                  startTime = record.long("start_time"),
                  endTime = record.long("end_time"),
                  place = record.string("place"),
                  images = extractRecordImages(record),
                  isOpen = record.int("isopen") == 1,
                  state = record.int("state"),
                  createTimeLabel = record.string("create_time_fmt"),
              )
            },
        total = payload.int("total") ?: 0,
    )
  }

  private suspend fun uploadPhoto(session: LocalYgdkSession, photo: YgdkPhotoUpload): String {
    val response =
        LocalUpstreamClientProvider.shared().post(
            localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Upload/File/post")
        ) {
          header("X-Requested-With", "XMLHttpRequest")
          setBody(
              MultiPartFormDataContent(
                  formData {
                    append("uid", session.uid.toString())
                    append("token", session.token)
                    append(
                        "file",
                        photo.bytes,
                        Headers.build {
                          append(
                              HttpHeaders.ContentDisposition,
                              ContentDisposition.File.withParameter(
                                      ContentDisposition.Parameters.Name,
                                      "file",
                                  )
                                  .withParameter(
                                      ContentDisposition.Parameters.FileName,
                                      photo.fileName,
                                  )
                                  .toString(),
                          )
                          append(HttpHeaders.ContentType, photo.mimeType)
                        },
                    )
                  }
              )
          )
        }
    val payload = unwrapYgdkResponse(response.bodyAsText()).jsonObject
    return payload.string("file_name") ?: throw ApiCallException("阳光打卡图片上传失败", code = "ygdk_error")
  }

  private suspend fun clockin(
      session: LocalYgdkSession,
      classifyId: Int,
      item: LocalYgdkItemRaw,
      startAt: LocalDateTime,
      endAt: LocalDateTime,
      place: String,
      imageName: String,
      isOpen: Boolean,
  ): LocalYgdkClockinResultRaw {
    val payload =
        postForm(
                session = session,
                url =
                    localUpstreamUrl("https://ygdk.buaa.edu.cn/api/Front/Clockin/Clockin/clockin"),
                formParameters =
                    Parameters.build {
                      append(
                          "start_time",
                          startAt.toInstant(LOCAL_YGDK_TIME_ZONE).epochSeconds.toString(),
                      )
                      append(
                          "end_time",
                          endAt.toInstant(LOCAL_YGDK_TIME_ZONE).epochSeconds.toString(),
                      )
                      append("place_type", "1")
                      append("place", place)
                      append("isopen", if (isOpen) "1" else "0")
                      append("form_time_fmt", formatClockinTimeRange(startAt, endAt))
                      append("images", "[\"$imageName\"]")
                      append("classify_id", classifyId.toString())
                      append("item_id", item.itemId.toString())
                      append("item_name", item.name)
                    },
            )
            .jsonObject
    return LocalYgdkClockinResultRaw(
        recordId = payload.int("record_id"),
        termId = payload.int("term_id"),
        termCount = payload.int("term_count"),
        termCountShow = payload.int("term_count_show"),
        termGoodCount = payload.int("term_good_count"),
        termGoodCountShow = payload.int("term_good_count_show"),
        weekCount = payload.int("week_count"),
        weekNum = payload.int("week_num"),
        monthCount = payload.int("month_count"),
        monthNum = payload.int("month_num"),
        dayCount = payload.int("day_count"),
        termNum = payload.int("term_num"),
    )
  }

  private suspend fun postForm(
      session: LocalYgdkSession,
      url: String,
      queryParameters: Parameters = Parameters.Empty,
      formParameters: Parameters = Parameters.Empty,
  ): JsonElement {
    val body =
        Parameters.build {
          formParameters.names().forEach { name ->
            formParameters.getAll(name).orEmpty().forEach { append(name, it) }
          }
          append("uid", session.uid.toString())
          append("token", session.token)
        }
    val response =
        LocalUpstreamClientProvider.shared().post(url) {
          header("X-Requested-With", "XMLHttpRequest")
          header(HttpHeaders.ContentType, "application/x-www-form-urlencoded; charset=UTF-8")
          queryParameters.names().forEach { name ->
            queryParameters.getAll(name).orEmpty().forEach { value -> parameter(name, value) }
          }
          setBody(FormDataContent(body))
        }
    return unwrapYgdkResponse(response.bodyAsText())
  }

  private fun unwrapYgdkResponse(bodyText: String): JsonElement {
    val payload =
        runCatching { json.parseToJsonElement(bodyText).jsonObject }
            .getOrElse { throw ApiCallException("阳光打卡返回无法解析", code = "ygdk_error") }
    return when (payload.int("code")) {
      1 -> payload["result"] ?: JsonNull
      -98 -> throw LocalYgdkAuthenticationException()
      else ->
          throw ApiCallException(
              payload.string("msg")
                  ?: userFacingMessageForCode("ygdk_error", HttpStatusCode.BadGateway),
              status = HttpStatusCode.BadGateway,
              code = "ygdk_error",
          )
    }
  }

  private fun resolveSportsClassify(classifies: List<LocalYgdkClassifyRaw>): LocalYgdkClassifyRaw {
    if (classifies.isEmpty()) throw ApiCallException("未获取到阳光打卡分类", code = "ygdk_error")
    return classifies.firstOrNull { it.name.contains("体育") }
        ?: classifies.firstOrNull { it.classifyId == 1 }
        ?: classifies.first()
  }

  private fun resolveDefaultItem(items: List<LocalYgdkItemRaw>): LocalYgdkItemRaw {
    if (items.isEmpty()) throw ApiCallException("未获取到阳光打卡项目列表", code = "ygdk_error")
    return items.firstOrNull { it.name.contains("跑") }
        ?: items.sortedBy { it.sort ?: Int.MAX_VALUE }.first()
  }

  private fun mapYgdkSummary(
      classify: LocalYgdkClassifyRaw,
      count: LocalYgdkCountRaw?,
      term: LocalYgdkTermRaw?,
  ): YgdkTermSummaryDto =
      YgdkTermSummaryDto(
          termId = term?.termId ?: term?.id,
          termName = term?.name,
          termCount =
              count?.termGoodCountShow
                  ?: count?.termGoodCount
                  ?: count?.termCountShow
                  ?: count?.termCount
                  ?: 0,
          termTarget = count?.termNum ?: classify.termNum,
          weekCount = count?.weekCount,
          weekTarget = count?.weekNum ?: classify.weekNum,
          monthCount = count?.monthCount,
          monthTarget = count?.monthNum ?: classify.monthNum,
          dayCount = count?.dayCount,
          goodCount = count?.termGoodCountShow ?: count?.termGoodCount,
      )

  private fun mapClockinSummary(
      classify: LocalYgdkClassifyRaw,
      result: LocalYgdkClockinResultRaw,
  ): YgdkTermSummaryDto =
      YgdkTermSummaryDto(
          termId = result.termId,
          termCount =
              result.termGoodCountShow
                  ?: result.termGoodCount
                  ?: result.termCountShow
                  ?: result.termCount
                  ?: 0,
          termTarget = result.termNum ?: classify.termNum,
          weekCount = result.weekCount,
          weekTarget = result.weekNum ?: classify.weekNum,
          monthCount = result.monthCount,
          monthTarget = result.monthNum ?: classify.monthNum,
          dayCount = result.dayCount,
          goodCount = result.termGoodCountShow ?: result.termGoodCount,
      )

  private fun LocalYgdkItemRaw.toDto(): YgdkItemDto =
      YgdkItemDto(itemId = itemId, name = name, type = type, sort = sort)

  private fun LocalYgdkRecordRaw.toDto(itemMap: Map<Int, LocalYgdkItemRaw>): YgdkRecordDto =
      YgdkRecordDto(
          recordId = recordId,
          itemId = itemId,
          itemName = itemName ?: itemId?.let { itemMap[it]?.name },
          startTime = timestampToDateTimeText(startTime),
          endTime = timestampToDateTimeText(endTime),
          place = place,
          images = images,
          isOpen = isOpen,
          state = state,
          createdAt = createTimeLabel,
          createdAtLabel = createTimeLabel,
      )

  private fun resolveClockinTimeRange(
      startTime: String?,
      endTime: String?,
  ): Pair<LocalDateTime, LocalDateTime> {
    val normalizedStart = startTime?.trim().orEmpty()
    val normalizedEnd = endTime?.trim().orEmpty()
    if (
        (normalizedStart.isBlank() && normalizedEnd.isNotBlank()) ||
            (normalizedStart.isNotBlank() && normalizedEnd.isBlank())
    ) {
      throw ApiCallException(
          "开始时间和结束时间需要同时填写",
          status = HttpStatusCode.BadRequest,
          code = "invalid_request",
      )
    }
    if (normalizedStart.isBlank() && normalizedEnd.isBlank()) {
      return generateDefaultClockinTimeRange()
    }

    val startAt = parseClockinDateTime(normalizedStart)
    val endAt = parseClockinDateTime(normalizedEnd)
    if (startAt.date != endAt.date) {
      throw ApiCallException(
          "当前仅支持同一天内的一小时打卡",
          status = HttpStatusCode.BadRequest,
          code = "invalid_request",
      )
    }
    if (endAt.toInstant(LOCAL_YGDK_TIME_ZONE) <= startAt.toInstant(LOCAL_YGDK_TIME_ZONE)) {
      throw ApiCallException(
          "结束时间必须晚于开始时间",
          status = HttpStatusCode.BadRequest,
          code = "invalid_request",
      )
    }
    return startAt to endAt
  }

  private fun parseClockinDateTime(value: String): LocalDateTime =
      runCatching { LocalDateTime.parse(value.replace(' ', 'T')) }
          .getOrElse {
            throw ApiCallException(
                "时间格式错误，请使用 yyyy-MM-dd HH:mm",
                status = HttpStatusCode.BadRequest,
                code = "invalid_request",
            )
          }

  private fun generateDefaultClockinTimeRange(): Pair<LocalDateTime, LocalDateTime> {
    val now = Clock.System.now().toLocalDateTime(LOCAL_YGDK_TIME_ZONE)
    val startHour = (now.hour - 1).coerceIn(8, 21)
    val usePreviousDay = now.hour < 9
    val startDate =
        if (usePreviousDay)
            (Clock.System.now() - 24.hours).toLocalDateTime(LOCAL_YGDK_TIME_ZONE).date
        else now.date
    val resolvedStartHour = if (usePreviousDay) 20 else startHour
    val startAt =
        LocalDateTime(
            year = startDate.year,
            month = startDate.month,
            day = startDate.day,
            hour = resolvedStartHour,
            minute = 0,
            second = 0,
            nanosecond = 0,
        )
    return startAt to
        Instant.fromEpochSeconds(startAt.toInstant(LOCAL_YGDK_TIME_ZONE).epochSeconds + 3600)
            .toLocalDateTime(LOCAL_YGDK_TIME_ZONE)
  }
}

private class LocalYgdkAuthenticationException(message: String? = null) : Exception(message)

private data class LocalYgdkSession(
    val studentId: String,
    val uid: Int,
    val token: String,
)

private data class LocalYgdkClassifyRaw(
    val classifyId: Int,
    val name: String,
    val termNum: Int? = null,
    val monthNum: Int? = null,
    val weekNum: Int? = null,
)

private data class LocalYgdkItemRaw(
    val itemId: Int,
    val name: String,
    val type: Int? = null,
    val sort: Int? = null,
)

private data class LocalYgdkCountRaw(
    val termCount: Int? = null,
    val termCountShow: Int? = null,
    val termGoodCount: Int? = null,
    val termGoodCountShow: Int? = null,
    val weekCount: Int? = null,
    val weekNum: Int? = null,
    val monthCount: Int? = null,
    val monthNum: Int? = null,
    val dayCount: Int? = null,
    val termNum: Int? = null,
)

private data class LocalYgdkTermRaw(
    val termId: Int? = null,
    val id: Int? = null,
    val name: String? = null,
)

private data class LocalYgdkRecordRaw(
    val recordId: Int,
    val itemId: Int? = null,
    val itemName: String? = null,
    val startTime: Long? = null,
    val endTime: Long? = null,
    val place: String? = null,
    val images: List<String> = emptyList(),
    val isOpen: Boolean = false,
    val state: Int? = null,
    val createTimeLabel: String? = null,
)

private data class LocalYgdkRecordsPageRaw(
    val records: List<LocalYgdkRecordRaw> = emptyList(),
    val total: Int = 0,
)

private data class LocalYgdkClockinResultRaw(
    val recordId: Int? = null,
    val termId: Int? = null,
    val termCount: Int? = null,
    val termCountShow: Int? = null,
    val termGoodCount: Int? = null,
    val termGoodCountShow: Int? = null,
    val weekCount: Int? = null,
    val weekNum: Int? = null,
    val monthCount: Int? = null,
    val monthNum: Int? = null,
    val dayCount: Int? = null,
    val termNum: Int? = null,
)

private fun JsonObject.int(name: String): Int? = this[name]?.jsonPrimitive?.intOrNull

private fun JsonObject.long(name: String): Long? =
    this[name]?.jsonPrimitive?.contentOrNull?.toLongOrNull()

private fun JsonObject.string(name: String): String? =
    this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }

private fun extractRecordImages(source: JsonObject): List<String> {
  source["images_fmt"]?.let { formatted ->
    when (formatted) {
      is kotlinx.serialization.json.JsonArray ->
          return formatted.mapNotNull { it.jsonPrimitive.contentOrNull }
      is kotlinx.serialization.json.JsonPrimitive ->
          formatted.contentOrNull
              ?.takeIf { it.isNotBlank() }
              ?.let {
                return listOf(it)
              }
      else -> Unit
    }
  }
  val rawImages = source.string("images") ?: return emptyList()
  val parser = Json { ignoreUnknownKeys = true }
  return runCatching {
        parser.parseToJsonElement(rawImages).jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }
      }
      .getOrElse { emptyList() }
}

private fun timestampToDateTimeText(timestampSeconds: Long?): String? {
  if (timestampSeconds == null) return null
  return Instant.fromEpochSeconds(timestampSeconds)
      .toLocalDateTime(LOCAL_YGDK_TIME_ZONE)
      .toYgdkDateTimeText()
}

private fun formatClockinTimeRange(startAt: LocalDateTime, endAt: LocalDateTime): String =
    "${startAt.toYgdkDateTimeText()}-${endAt.hour.toString().padStart(2, '0')}:${endAt.minute.toString().padStart(2, '0')}"

private fun LocalDateTime.toYgdkDateTimeText(): String =
    "${date.year}-${(date.month.ordinal + 1).toString().padStart(2, '0')}-${date.day.toString().padStart(2, '0')} " +
        "${hour.toString().padStart(2, '0')}:${minute.toString().padStart(2, '0')}"

private fun extractOauthCode(url: String): String? =
    url.substringAfter('?', missingDelimiterValue = "")
        .split('&')
        .firstOrNull { it.startsWith("code=") }
        ?.substringAfter("code=")
        ?.decodeURLQueryComponent()

private fun resolveRedirectUrl(currentUrl: Url, location: String): String {
  if (location.startsWith("http://") || location.startsWith("https://")) {
    return localUpstreamUrl(location)
  }
  if (location.startsWith("//")) {
    return "${currentUrl.protocol.name}:$location"
  }
  val authority =
      "${currentUrl.protocol.name}://${currentUrl.host}${if (currentUrl.specifiedPort != currentUrl.protocol.defaultPort) ":${currentUrl.specifiedPort}" else ""}"
  if (location.startsWith("/")) {
    return "$authority$location"
  }
  val basePath = currentUrl.encodedPath.substringBeforeLast('/', "")
  val separator = if (basePath.endsWith("/")) "" else "/"
  return "$authority$basePath$separator$location"
}

@OptIn(ExperimentalEncodingApi::class)
private fun defaultTransparentPhotoBytes(): ByteArray =
    Base64.decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+lmCcAAAAASUVORK5CYII="
    )

private val LOCAL_YGDK_TIME_ZONE = TimeZone.of("Asia/Shanghai")

private const val DEFAULT_YGDK_PLACE = "操场"

private fun localYgdkOauthUrl(): String =
    localUpstreamUrl(
        "https://app.buaa.edu.cn/uc/api/oauth/index?redirect=https%3A%2F%2Fygdk.buaa.edu.cn%2F%23%2Fhome&appid=200230221144501510&state=STATE&qrcode=1"
    )
