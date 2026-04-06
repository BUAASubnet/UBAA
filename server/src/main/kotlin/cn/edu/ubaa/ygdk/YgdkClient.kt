package cn.edu.ubaa.ygdk

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.forms.MultiPartFormDataContent
import io.ktor.client.request.forms.formData
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentDisposition
import io.ktor.http.ContentType
import io.ktor.http.Headers
import io.ktor.http.HttpHeaders
import io.ktor.http.Parameters
import io.ktor.http.contentType
import io.ktor.http.withCharset
import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

internal data class YgdkAuthData(val uid: Int, val token: String)

internal data class YgdkClassifyRaw(
    val classifyId: Int,
    val name: String,
    val termNum: Int? = null,
    val monthNum: Int? = null,
    val weekNum: Int? = null,
)

internal data class YgdkItemRaw(
    val itemId: Int,
    val name: String,
    val type: Int? = null,
    val sort: Int? = null,
)

internal data class YgdkCountRaw(
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

internal data class YgdkTermRaw(
    val termId: Int? = null,
    val id: Int? = null,
    val name: String? = null,
)

internal data class YgdkRecordRaw(
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

internal data class YgdkRecordsPageRaw(
    val records: List<YgdkRecordRaw> = emptyList(),
    val total: Int = 0,
)

internal data class YgdkUploadedFileRaw(
    val fileName: String,
    val fileUrl: String? = null,
)

internal data class YgdkClockinResultRaw(
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

internal open class YgdkClient(
    private val username: String,
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
) {
  private val json = Json { ignoreUnknownKeys = true }
  private var authData: YgdkAuthData? = null
  private val authMutex = Mutex()

  open suspend fun getClassifyList(): List<YgdkClassifyRaw> {
    val result = postForm(operation = "get_classify_list", path = "/Front/Clockin/Classify/getList")
    val list = result.jsonObject["list"]?.jsonArray.orEmpty()
    return list.mapNotNull { it.jsonObjectOrNull()?.toClassifyRaw() }
  }

  open suspend fun getItemList(classifyId: Int): List<YgdkItemRaw> {
    val parameters =
        Parameters.build {
          append("page", "1")
          append("limit", "1000")
          append("classify_id", classifyId.toString())
        }
    val result =
        postForm(
            operation = "get_item_list",
            path = "/Front/Clockin/Item/getList",
            queryParameters = parameters,
            formParameters = parameters,
        )
    val list = result.jsonObject["list"]?.jsonArray.orEmpty()
    return list.mapNotNull { it.jsonObjectOrNull()?.toItemRaw() }
  }

  open suspend fun getCheckCount(classifyId: Int): YgdkCountRaw {
    ensureLogin()
    val uid = authData?.uid ?: throw YgdkAuthenticationException()
    val result =
        postForm(
            operation = "get_check_count",
            path = "/Front/Clockin/Clockin/getCount",
            formParameters =
                Parameters.build {
                  append("classify_id", classifyId.toString())
                  append("user_id", uid.toString())
                },
        )
    return result.jsonObject.toCountRaw()
  }

  open suspend fun getTerm(): YgdkTermRaw {
    val result = postForm(operation = "get_term", path = "/Front/Clockin/Term/get")
    val obj = result.jsonObject
    return YgdkTermRaw(
        termId = obj.int("term_id"),
        id = obj.int("id"),
        name = obj.string("name"),
    )
  }

  open suspend fun getRecords(classifyId: Int, page: Int, limit: Int): YgdkRecordsPageRaw {
    ensureLogin()
    val uid = authData?.uid ?: throw YgdkAuthenticationException()
    val result =
        postForm(
            operation = "get_records",
            path = "/Front/Clockin/Clockin/getList",
            formParameters =
                Parameters.build {
                  append("page", page.toString())
                  append("limit", limit.toString())
                  append("classify_id", classifyId.toString())
                  append("user_id", uid.toString())
                },
        )
    val obj = result.jsonObject
    return YgdkRecordsPageRaw(
        records =
            obj["list"]?.jsonArray.orEmpty().mapNotNull { it.jsonObjectOrNull()?.toRecordRaw() },
        total = obj.int("total") ?: 0,
    )
  }

  open suspend fun uploadImage(
      bytes: ByteArray,
      fileName: String,
      mimeType: String,
  ): YgdkUploadedFileRaw {
    ensureLogin()
    val auth = authData ?: throw YgdkAuthenticationException()
    val session = sessionManager.requireSession(username)
    val response =
        AppObservability.observeUpstreamRequest("ygdk", "upload_image") {
          session.client.post("$API_BASE/Front/Upload/File/post") {
            header("X-Requested-With", "XMLHttpRequest")
            setBody(
                MultiPartFormDataContent(
                    formData {
                      append("uid", auth.uid.toString())
                      append("token", auth.token)
                      append(
                          "file",
                          bytes,
                          Headers.build {
                            append(
                                HttpHeaders.ContentDisposition,
                                ContentDisposition.File.withParameter(
                                        ContentDisposition.Parameters.Name,
                                        "file",
                                    )
                                    .withParameter(ContentDisposition.Parameters.FileName, fileName)
                                    .toString(),
                            )
                            append(HttpHeaders.ContentType, mimeType)
                          },
                      )
                    }
                )
            )
          }
        }
    val result = unwrapResponse(response.bodyAsText())
    val obj = result.jsonObject
    return YgdkUploadedFileRaw(
        fileName = obj.string("file_name") ?: throw YgdkException("阳光打卡图片上传失败"),
        fileUrl = obj.string("file_url"),
    )
  }

  open suspend fun clockin(
      classifyId: Int,
      itemId: Int,
      itemName: String,
      startAt: LocalDateTime,
      endAt: LocalDateTime,
      place: String,
      imageName: String,
      isOpen: Boolean,
      placeType: Int = 1,
  ): YgdkClockinResultRaw {
    val zoneId = ZoneId.of(CHINA_ZONE_ID)
    val result =
        postForm(
            operation = "clockin",
            path = "/Front/Clockin/Clockin/clockin",
            formParameters =
                Parameters.build {
                  append("start_time", startAt.atZone(zoneId).toEpochSecond().toString())
                  append("end_time", endAt.atZone(zoneId).toEpochSecond().toString())
                  append("place_type", placeType.toString())
                  append("place", place)
                  append("isopen", if (isOpen) "1" else "0")
                  append("form_time_fmt", formatFormTime(startAt, endAt))
                  append("images", "[\"$imageName\"]")
                  append("classify_id", classifyId.toString())
                  append("item_id", itemId.toString())
                  append("item_name", itemName)
                },
        )
    return result.jsonObject.toClockinResultRaw()
  }

  open fun close() {
    authData = null
  }

  private suspend fun ensureLogin(forceRefresh: Boolean = false) {
    if (!forceRefresh && authData != null) return
    authMutex.withLock {
      if (!forceRefresh && authData != null) return@withLock
      val code = fetchOauthCode()
      authData = exchangeCode(code)
    }
  }

  private suspend fun fetchOauthCode(): String {
    val session = sessionManager.requireSession(username)
    val noRedirectClient = session.client.config { followRedirects = false }
    try {
      var currentUrl = OAUTH_URL
      repeat(10) {
        val response =
            AppObservability.observeUpstreamRequest("app_buaa", "fetch_oauth_code") {
              noRedirectClient.get(currentUrl)
            }
        extractCodeFromUrl(response.call.request.url.toString())?.let {
          return it
        }
        val location = response.headers[HttpHeaders.Location]
        if (location.isNullOrBlank()) return@repeat
        val nextUrl = resolveUrl(response.call.request.url.toString(), location)
        extractCodeFromUrl(nextUrl)?.let {
          return it
        }
        currentUrl = nextUrl
      }
    } finally {
      noRedirectClient.close()
    }
    throw YgdkAuthenticationException("无法获取阳光打卡登录 code，请重新登录 UBAA")
  }

  private suspend fun exchangeCode(code: String): YgdkAuthData {
    val session = sessionManager.requireSession(username)
    val response =
        AppObservability.observeUpstreamRequest("ygdk", "exchange_code") {
          session.client.get("$API_BASE/Front/Clockin/User/campusAppLogin") {
            url.parameters.append("code", code)
          }
        }
    val result = unwrapResponse(response.bodyAsText())
    val data = result.jsonObject["data"]?.jsonObject ?: result.jsonObject
    val uid = data.int("uid") ?: throw YgdkAuthenticationException("阳光打卡返回 uid 缺失")
    val token =
        data.string("token")?.let { URLDecoder.decode(it, StandardCharsets.UTF_8.name()) }
            ?: throw YgdkAuthenticationException("阳光打卡返回 token 缺失")
    return YgdkAuthData(uid = uid, token = token)
  }

  private suspend fun postForm(
      operation: String,
      path: String,
      queryParameters: Parameters = Parameters.Empty,
      formParameters: Parameters = Parameters.Empty,
  ): JsonElement {
    ensureLogin()
    val auth = authData ?: throw YgdkAuthenticationException()
    val session = sessionManager.requireSession(username)
    val body =
        Parameters.build {
          formParameters.names().forEach { name ->
            formParameters.getAll(name).orEmpty().forEach { append(name, it) }
          }
          append("uid", auth.uid.toString())
          append("token", auth.token)
        }
    val response =
        AppObservability.observeUpstreamRequest("ygdk", operation) {
          session.client.post("$API_BASE$path") {
            header("X-Requested-With", "XMLHttpRequest")
            contentType(FORM_CONTENT_TYPE)
            queryParameters.names().forEach { name ->
              queryParameters.getAll(name).orEmpty().forEach { value ->
                url.parameters.append(name, value)
              }
            }
            setBody(FormDataContent(body))
          }
        }
    return unwrapResponse(response.bodyAsText())
  }

  private fun unwrapResponse(bodyText: String): JsonElement {
    val payload =
        try {
          json.parseToJsonElement(bodyText).jsonObject
        } catch (e: Exception) {
          throw YgdkException("阳光打卡返回无法解析", cause = e)
        }
    return when (payload.int("code")) {
      1 -> payload["result"] ?: JsonNull
      -98 -> {
        authData = null
        throw YgdkAuthenticationException()
      }
      else -> throw YgdkException(payload.string("msg") ?: "阳光打卡请求失败")
    }
  }

  private fun resolveUrl(baseUrl: String, location: String): String {
    return URI.create(baseUrl).resolve(location).toString()
  }

  private fun extractCodeFromUrl(url: String): String? {
    val uri = URI.create(url)
    val queries = buildList {
      uri.query?.let { add(it) }
      uri.fragment?.let { fragment ->
        val query = fragment.substringAfter('?', missingDelimiterValue = "")
        if (query.isNotBlank()) add(query)
      }
    }
    return queries.firstNotNullOfOrNull { query -> parseQueryValue(query, "code") }
  }

  private fun parseQueryValue(query: String, key: String): String? {
    return query
        .split('&')
        .mapNotNull { pair ->
          val parts = pair.split('=', limit = 2)
          if (parts.size != 2 || parts[0] != key) null
          else URLDecoder.decode(parts[1], StandardCharsets.UTF_8.name())
        }
        .firstOrNull()
  }

  private fun formatFormTime(startAt: LocalDateTime, endAt: LocalDateTime): String {
    return "${startAt.format(FORMATTER_DAY_TIME)}-${endAt.format(FORMATTER_TIME)}"
  }

  private fun JsonElement.jsonObjectOrNull(): JsonObject? = this as? JsonObject

  private fun JsonObject.toClassifyRaw(): YgdkClassifyRaw? {
    val classifyId = int("classify_id") ?: return null
    val name = string("name") ?: return null
    return YgdkClassifyRaw(
        classifyId = classifyId,
        name = name,
        termNum = int("term_num"),
        monthNum = int("month_num"),
        weekNum = int("week_num"),
    )
  }

  private fun JsonObject.toItemRaw(): YgdkItemRaw? {
    val itemId = int("item_id") ?: return null
    val name = string("name") ?: return null
    return YgdkItemRaw(
        itemId = itemId,
        name = name,
        type = int("type"),
        sort = int("sort"),
    )
  }

  private fun JsonObject.toCountRaw(): YgdkCountRaw {
    return YgdkCountRaw(
        termCount = int("term_count"),
        termCountShow = int("term_count_show"),
        termGoodCount = int("term_good_count"),
        termGoodCountShow = int("term_good_count_show"),
        weekCount = int("week_count"),
        weekNum = int("week_num"),
        monthCount = int("month_count"),
        monthNum = int("month_num"),
        dayCount = int("day_count"),
        termNum = int("term_num"),
    )
  }

  private fun JsonObject.toRecordRaw(): YgdkRecordRaw? {
    val recordId = int("record_id") ?: return null
    return YgdkRecordRaw(
        recordId = recordId,
        itemId = int("item_id"),
        itemName = string("item_name"),
        startTime = long("start_time"),
        endTime = long("end_time"),
        place = string("place"),
        images = extractImages(this),
        isOpen = int("isopen") == 1,
        state = int("state"),
        createTimeLabel = string("create_time_fmt"),
    )
  }

  private fun JsonObject.toClockinResultRaw(): YgdkClockinResultRaw {
    return YgdkClockinResultRaw(
        recordId = int("record_id"),
        termId = int("term_id"),
        termCount = int("term_count"),
        termCountShow = int("term_count_show"),
        termGoodCount = int("term_good_count"),
        termGoodCountShow = int("term_good_count_show"),
        weekCount = int("week_count"),
        weekNum = int("week_num"),
        monthCount = int("month_count"),
        monthNum = int("month_num"),
        dayCount = int("day_count"),
        termNum = int("term_num"),
    )
  }

  private fun extractImages(source: JsonObject): List<String> {
    source["images_fmt"]?.let { formatted ->
      when (formatted) {
        is JsonArray -> return formatted.mapNotNull { it.jsonPrimitive.contentOrNull }
        is JsonPrimitive -> {
          val content = formatted.contentOrNull
          if (!content.isNullOrBlank()) return listOf(content)
        }
        else -> Unit
      }
    }
    val rawImages = source.string("images") ?: return emptyList()
    return runCatching {
          json.parseToJsonElement(rawImages).jsonArray.mapNotNull { it.jsonPrimitive.contentOrNull }
        }
        .getOrElse { emptyList() }
  }

  private fun JsonObject.int(name: String): Int? = this[name]?.jsonPrimitive?.intOrNull

  private fun JsonObject.long(name: String): Long? =
      this[name]?.jsonPrimitive?.contentOrNull?.toLongOrNull()

  private fun JsonObject.string(name: String): String? =
      this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }

  companion object {
    private const val YGDK_FRONT_BASE = "https://ygdk.buaa.edu.cn"
    private const val API_BASE = "$YGDK_FRONT_BASE/api"
    private const val APP_ID = "200230221144501510"
    private const val CHINA_ZONE_ID = "Asia/Shanghai"
    private val FORM_CONTENT_TYPE =
        ContentType.Application.FormUrlEncoded.withCharset(Charsets.UTF_8)
    private val FORMATTER_DAY_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")
    private val FORMATTER_TIME = DateTimeFormatter.ofPattern("HH:mm")
    private val OAUTH_URL =
        "https://app.buaa.edu.cn/uc/api/oauth/index?redirect=" +
            java.net.URLEncoder.encode("$YGDK_FRONT_BASE/#/home", StandardCharsets.UTF_8.name()) +
            "&appid=$APP_ID&state=STATE&qrcode=1"

    fun timestampToDateTimeText(timestampSeconds: Long?): String? {
      if (timestampSeconds == null) return null
      return LocalDateTime.ofInstant(
              Instant.ofEpochSecond(timestampSeconds),
              ZoneId.of(CHINA_ZONE_ID),
          )
          .format(FORMATTER_DAY_TIME)
    }
  }
}
