package cn.edu.ubaa.cgyy

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
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
import io.ktor.http.Parameters
import io.ktor.http.Url
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class CgyyApiEnvelope(
    val data: JsonElement?,
    val message: String,
    val raw: JsonObject,
)

interface CgyyGateway {
  suspend fun getVenueSites(): JsonArray

  suspend fun getPurposeTypesRaw(): JsonElement?

  suspend fun getReservationDayInfo(searchDate: String, venueSiteId: Int): JsonObject

  suspend fun createReservationOrder(
      venueSiteId: Int,
      reservationDate: String,
      weekStartDate: String,
      reservationOrderJson: String,
      token: String,
  ): CgyyApiEnvelope

  suspend fun getCaptcha(): CgyyCaptchaChallenge

  suspend fun verifyCaptcha(pointJson: String, token: String): JsonObject

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
  ): CgyyApiEnvelope

  suspend fun getMineOrders(page: Int, size: Int): JsonObject

  suspend fun getOrderDetail(orderId: Int): JsonObject

  suspend fun cancelOrder(orderId: Int): CgyyApiEnvelope

  suspend fun getLockCode(): JsonElement?

  fun close()
}

class CgyyZhjsClient(
    private val username: String,
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val signer: CgyySigner = CgyySigner(),
) : CgyyGateway {
  private val json = Json { ignoreUnknownKeys = true }
  private val loginMutex = Mutex()

  @Volatile private var accessToken: String? = null

  override suspend fun getVenueSites(): JsonArray {
    val data =
        requestJson(
                operation = "list_sites",
                HttpMethod.Get,
                "/api/front/website/venues",
                params = mapOf("page" to -1, "size" to -1, "reservationRoleId" to 3),
            )
            .data
    return data.asVenueSiteArray()
  }

  override suspend fun getPurposeTypesRaw(): JsonElement? {
    return requestJson(
            operation = "list_purpose_types",
            method = HttpMethod.Get,
            path = "/api/codes",
        )
        .data
  }

  override suspend fun getReservationDayInfo(searchDate: String, venueSiteId: Int): JsonObject {
    val response =
        requestJson(
            operation = "get_day_info",
            method = HttpMethod.Get,
            path = "/api/reservation/day/info",
            params = mapOf("searchDate" to searchDate, "venueSiteId" to venueSiteId),
        )
    return response.data?.jsonObject ?: throw CgyyException("研讨室可用性响应为空", "day_info_failed")
  }

  override suspend fun createReservationOrder(
      venueSiteId: Int,
      reservationDate: String,
      weekStartDate: String,
      reservationOrderJson: String,
      token: String,
  ): CgyyApiEnvelope {
    return requestJson(
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
  }

  override suspend fun getCaptcha(): CgyyCaptchaChallenge {
    val now = System.currentTimeMillis()
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
            ?.jsonObject ?: throw CgyyException("验证码响应为空", "captcha_error")
    val success = data["success"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() ?: false
    if (!success) {
      throw CgyyException(
          data["repMsg"]?.jsonPrimitive?.contentOrNull ?: "获取验证码失败",
          "captcha_error",
      )
    }
    val repData = data["repData"]?.jsonObject ?: throw CgyyException("验证码数据缺失", "captcha_error")
    return CgyyCaptchaChallenge(
        secretKey = repData.requireString("secretKey"),
        token = repData.requireString("token"),
        originalImageBase64 = repData.requireString("originalImageBase64"),
        jigsawImageBase64 = repData.requireString("jigsawImageBase64"),
    )
  }

  override suspend fun verifyCaptcha(pointJson: String, token: String): JsonObject {
    val data =
        requestJson(
                operation = "verify_captcha",
                method = HttpMethod.Post,
                path = "/api/captcha/check",
                form = mapOf("pointJson" to pointJson, "token" to token),
            )
            .data
            ?.jsonObject ?: throw CgyyException("验证码校验响应为空", "captcha_error")
    val success = data["success"]?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() ?: false
    if (!success) {
      throw CgyyException(
          data["repMsg"]?.jsonPrimitive?.contentOrNull ?: "验证码校验失败",
          "captcha_error",
      )
    }
    return data
  }

  override suspend fun submitReservationOrder(
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
  ): CgyyApiEnvelope {
    return requestJson(
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
  }

  override suspend fun getMineOrders(page: Int, size: Int): JsonObject {
    val response =
        requestJson(
            operation = "list_orders",
            method = HttpMethod.Get,
            path = "/api/orders/mine",
            params = mapOf("page" to page, "size" to size),
        )
    return response.data?.jsonObject ?: buildJsonObject {}
  }

  override suspend fun getOrderDetail(orderId: Int): JsonObject {
    val response =
        requestJson(
            operation = "get_order_detail",
            method = HttpMethod.Get,
            path = "/api/orders/$orderId",
        )
    return response.data?.jsonObject ?: buildJsonObject {}
  }

  override suspend fun cancelOrder(orderId: Int): CgyyApiEnvelope {
    return requestJson(
        operation = "cancel_order",
        method = HttpMethod.Post,
        path = "/api/orders/new/cancel/$orderId",
    )
  }

  override suspend fun getLockCode(): JsonElement? {
    return requestJson(
            operation = "get_lock_code",
            method = HttpMethod.Get,
            path = "/api/orders/lock/code",
        )
        .data
  }

  override fun close() {}

  private suspend fun requestJson(
      operation: String,
      method: HttpMethod,
      path: String,
      params: Map<String, Any?> = emptyMap(),
      form: Map<String, Any?> = emptyMap(),
      extraHeaders: Map<String, String> = emptyMap(),
      includeAuthorization: Boolean = true,
      allowRetry: Boolean = true,
  ): CgyyApiEnvelope {
    val session = sessionManager.requireSession(username)
    if (includeAuthorization) {
      ensureBusinessLogin()
    }

    val timestamp = System.currentTimeMillis()
    val pathOnly = normalizePath(path)
    val requestParams =
        if (method == HttpMethod.Get) signer.addNoCacheIfMissing(params, timestamp) else params
    val signSource = if (method == HttpMethod.Get) requestParams else form
    val sign = signer.sign(pathOnly, signSource, timestamp)

    val response =
        AppObservability.observeUpstreamRequest("cgyy", operation) {
          session.client.request(buildUrl(pathOnly)) {
            this.method = method
            header(HttpHeaders.Accept, "application/json, text/plain, */*")
            header(HttpHeaders.Referrer, "https://cgyy.buaa.edu.cn/venue-zhjs/mobileReservation")
            header("app-key", signer.appKey)
            header("timestamp", timestamp.toString())
            header("sign", sign)
            if (includeAuthorization) {
              header("cgAuthorization", requireNotNull(accessToken) { "CGYY access token missing" })
            }
            extraHeaders.forEach { (key, value) -> header(key, value) }

            requestParams.forEach { (key, value) ->
              if (method == HttpMethod.Get && value != null) parameter(key, value.toString())
            }
            if (method != HttpMethod.Get) {
              val formParameters =
                  Parameters.build {
                    form.forEach { (key, value) ->
                      if (value != null) append(key, value.toString())
                    }
                  }
              setBody(FormDataContent(formParameters))
            }
          }
        }

    val body = response.bodyAsText()
    if (isLoginRedirect(response, body)) {
      accessToken = null
      if (!allowRetry) {
        throw CgyyException("研讨室系统登录状态失效", "unauthenticated")
      }
      ensureBusinessLogin()
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
            .getOrElse { throw CgyyException("研讨室系统返回了非 JSON 响应", "cgyy_error") }
    val code = raw["code"]?.jsonPrimitive?.intOrNull
    if (code != 200) {
      throw CgyyException(raw["message"]?.jsonPrimitive?.contentOrNull ?: "研讨室系统请求失败", "cgyy_error")
    }
    return CgyyApiEnvelope(
        data = raw["data"],
        message = raw["message"]?.jsonPrimitive?.contentOrNull ?: "OK",
        raw = raw,
    )
  }

  private suspend fun ensureBusinessLogin() {
    if (!accessToken.isNullOrBlank()) return
    loginMutex.withLock {
      if (!accessToken.isNullOrBlank()) return@withLock

      val session = sessionManager.requireSession(username)
      AppObservability.observeUpstreamRequest("cgyy", "manage_login") {
        session.client.get("$BASE_URL/sso/manageLogin")
      }
      val ssoToken =
          session.cookieStorage
              .get(Url("$BASE_URL"))
              .firstOrNull { it.name == SSO_COOKIE_NAME }
              ?.value
              ?.takeIf { it.isNotBlank() }
              ?: throw CgyyException("未获取到研讨室 SSO Token", "unauthenticated")

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
              ?.contentOrNull ?: throw CgyyException("研讨室登录成功但未返回 access_token", "unauthenticated")
    }
  }

  private fun isLoginRedirect(response: HttpResponse, body: String): Boolean {
    val finalUrl = response.call.request.url.toString()
    if (response.status.value == 401) return true
    if (finalUrl.contains("sso.buaa.edu.cn/login")) return true
    return body.contains("name=\"execution\"") && body.contains("username_password")
  }

  private fun buildUrl(path: String): String = "$BASE_URL${path.removePrefix("/")}"

  private fun normalizePath(path: String): String = if (path.startsWith("/")) path else "/$path"

  private fun JsonObject.requireString(key: String): String {
    return this[key]?.jsonPrimitive?.contentOrNull
        ?: throw CgyyException("响应缺少字段: $key", "cgyy_error")
  }

  private fun JsonElement?.asJsonArrayOrContent(): JsonArray {
    return when (this) {
      null -> JsonArray(emptyList())
      is JsonArray -> this
      is JsonObject -> this["content"]?.jsonArray ?: JsonArray(emptyList())
      else -> JsonArray(emptyList())
    }
  }

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
                  put("id", JsonPrimitive(siteId))
                  put("venueId", JsonPrimitive(venueId))
                  put(
                      "siteName",
                      JsonPrimitive(site["siteName"]?.jsonPrimitive?.contentOrNull.orEmpty()),
                  )
                  put("venueName", JsonPrimitive(venueName))
                  put("campusName", JsonPrimitive(campusName))
                }
              }
              .orEmpty()
        }
    )
  }

  companion object {
    const val BASE_URL = "https://cgyy.buaa.edu.cn/venue-zhjs-server/"
    private const val SSO_COOKIE_NAME = "sso_buaa_zhjs_token"
  }
}

class CgyyException(
    message: String,
    val code: String = "cgyy_error",
) : RuntimeException(message)
