package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.CaptchaInfo
import cn.edu.ubaa.model.dto.LoginPreloadResponse
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.LoginResponse
import cn.edu.ubaa.model.dto.LoginStatsSuccessMode
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfo
import cn.edu.ubaa.model.dto.UserInfoResponse
import com.russhwolf.settings.Settings
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.client.plugins.logging.LogLevel
import io.ktor.client.plugins.logging.Logging
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Cookie
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.serialization.kotlinx.json.json
import io.ktor.util.date.GMTDate
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi
import kotlin.time.Instant
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class LocalAuthSession(
    val username: String,
    val user: UserData,
    val authenticatedAt: String,
    val lastActivity: String,
)

object LocalAuthSessionStore {
  private const val KEY_LOCAL_AUTH_SESSION = "local_auth_session"
  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  private val json = Json { ignoreUnknownKeys = true }

  fun save(session: LocalAuthSession) {
    settings.putString(
        ModeScopedSessionStore.scopedKey(KEY_LOCAL_AUTH_SESSION),
        json.encodeToString(session),
    )
  }

  fun get(): LocalAuthSession? {
    val stored = settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_LOCAL_AUTH_SESSION))
    return stored?.let { json.decodeFromString<LocalAuthSession>(it) }
  }

  fun clear() {
    settings.remove(ModeScopedSessionStore.scopedKey(KEY_LOCAL_AUTH_SESSION))
  }

  fun clearAllScopes() {
    ConnectionMode.entries.forEach { mode ->
      settings.remove(ModeScopedSessionStore.scopedKey(KEY_LOCAL_AUTH_SESSION, mode))
    }
  }
}

internal object LocalCookieStore {
  private const val KEY_LOCAL_COOKIES = "local_connection_cookies"
  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  private val json = Json { ignoreUnknownKeys = true }

  fun storage(
      mode: ConnectionMode = ConnectionRuntime.currentMode() ?: ConnectionMode.DIRECT
  ): PersistentLocalCookieStorage = PersistentLocalCookieStorage(mode)

  fun clear(mode: ConnectionMode = ConnectionRuntime.currentMode() ?: ConnectionMode.DIRECT) {
    settings.remove(ModeScopedSessionStore.scopedKey(KEY_LOCAL_COOKIES, mode))
  }

  fun clearAllScopes() {
    ConnectionMode.entries.forEach { mode ->
      settings.remove(ModeScopedSessionStore.scopedKey(KEY_LOCAL_COOKIES, mode))
    }
  }

  internal fun load(mode: ConnectionMode): MutableList<StoredCookieRecord> {
    val stored = settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_LOCAL_COOKIES, mode))
    if (stored.isNullOrBlank()) {
      return mutableListOf()
    }
    return runCatching { json.decodeFromString<List<StoredCookieRecord>>(stored).toMutableList() }
        .getOrElse { mutableListOf() }
  }

  internal fun save(mode: ConnectionMode, records: List<StoredCookieRecord>) {
    if (records.isEmpty()) {
      clear(mode)
      return
    }
    settings.putString(
        ModeScopedSessionStore.scopedKey(KEY_LOCAL_COOKIES, mode),
        json.encodeToString(records),
    )
  }
}

@Serializable
internal data class StoredCookieRecord(
    val cookie: Cookie,
    val createdAtEpochMillis: Long,
)

internal class PersistentLocalCookieStorage(private val mode: ConnectionMode) : CookiesStorage {
  private val mutex = Mutex()

  override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
    mutex.withLock {
      val records = LocalCookieStore.load(mode)
      val normalized =
          cookie.copy(
              domain = (cookie.domain ?: requestUrl.host).lowercase(),
              path = cookie.path ?: defaultCookiePath(requestUrl.encodedPath),
          )
      val key = cookieKey(normalized)
      records.removeAll { cookieKey(it.cookie) == key }
      if ((normalized.maxAge ?: -1L) != 0L) {
        records += StoredCookieRecord(normalized, nowMillis())
      }
      LocalCookieStore.save(mode, records)
    }
  }

  override suspend fun get(requestUrl: Url): List<Cookie> =
      mutex.withLock {
        val now = nowMillis()
        val records = LocalCookieStore.load(mode)
        val active = mutableListOf<StoredCookieRecord>()
        val result = mutableListOf<Cookie>()
        records.forEach { record ->
          val cookie = record.cookie
          if (isExpired(cookie, record.createdAtEpochMillis, now)) {
            return@forEach
          }
          active += record
          if (!domainMatches(requestUrl.host, cookie.domain ?: requestUrl.host)) return@forEach
          if (!pathMatches(requestUrl.encodedPath, cookie.path ?: "/")) return@forEach
          if (cookie.secure && !requestUrl.protocol.name.equals("https", ignoreCase = true))
              return@forEach
          result += cookie.copy(expires = cookie.expires?.timestamp?.let(::GMTDate))
        }
        LocalCookieStore.save(mode, active)
        result
      }

  suspend fun clear() {
    mutex.withLock { LocalCookieStore.clear(mode) }
  }

  override fun close() = Unit

  private fun isExpired(cookie: Cookie, createdAt: Long, now: Long): Boolean {
    val expiresAt = cookie.expires?.timestamp
    if (expiresAt != null && expiresAt <= now) {
      return true
    }
    val maxAge = cookie.maxAge
    return maxAge != null && maxAge >= 0 && now >= createdAt + maxAge * 1000L
  }

  private fun cookieKey(cookie: Cookie): String =
      "${cookie.domain.orEmpty()}|${cookie.path.orEmpty()}|${cookie.name}"

  private fun defaultCookiePath(requestPath: String): String {
    val normalizedRequestPath = requestPath.ifBlank { "/" }
    if (!normalizedRequestPath.startsWith("/")) return "/"
    if (normalizedRequestPath == "/") return "/"
    val lastSlash = normalizedRequestPath.lastIndexOf('/')
    return if (lastSlash <= 0) "/" else normalizedRequestPath.substring(0, lastSlash)
  }

  private fun domainMatches(host: String, domain: String): Boolean {
    val normalizedHost = host.lowercase()
    val normalizedDomain = domain.trimStart('.').lowercase()
    return normalizedHost == normalizedDomain || normalizedHost.endsWith(".$normalizedDomain")
  }

  private fun pathMatches(requestPath: String, cookiePath: String): Boolean {
    val normalizedRequestPath = requestPath.ifBlank { "/" }
    val normalizedCookiePath = if (cookiePath.endsWith("/")) cookiePath else "$cookiePath/"
    return normalizedRequestPath.startsWith(normalizedCookiePath.removeSuffix("/"))
  }
}

internal object LocalUpstreamClientProvider {
  internal var clientFactory: (Boolean) -> HttpClient = { followRedirects ->
    buildLocalUpstreamClient(
        followRedirects = followRedirects,
        cookieStorage =
            LocalCookieStore.storage(
                ConnectionRuntime.currentMode()?.takeIf { it != ConnectionMode.SERVER_RELAY }
                    ?: ConnectionMode.DIRECT
            ),
    )
  }

  private val sharedClient =
      ResettableSharedInstance(factory = { clientFactory(true) }, disposer = HttpClient::close)

  fun shared(): HttpClient = sharedClient.getOrCreate()

  fun newNoRedirectClient(): HttpClient = clientFactory(false)

  fun reset() {
    sharedClient.reset()
    clientFactory = { followRedirects ->
      buildLocalUpstreamClient(
          followRedirects = followRedirects,
          cookieStorage =
              LocalCookieStore.storage(
                  ConnectionRuntime.currentMode()?.takeIf { it != ConnectionMode.SERVER_RELAY }
                      ?: ConnectionMode.DIRECT
              ),
      )
    }
  }
}

private fun buildLocalUpstreamClient(
    followRedirects: Boolean,
    cookieStorage: CookiesStorage,
): HttpClient {
  return HttpClient(getDefaultEngine()) {
    this.followRedirects = followRedirects
    install(ContentNegotiation) {
      json(
          Json {
            ignoreUnknownKeys = true
            isLenient = true
          }
      )
    }
    install(Logging) { level = LogLevel.INFO }
    install(HttpCookies) { storage = cookieStorage }
    install(HttpTimeout) {
      requestTimeoutMillis = 30_000
      connectTimeoutMillis = 10_000
      socketTimeoutMillis = 30_000
    }
  }
}

private val localConnectionAuthJson = Json { ignoreUnknownKeys = true }

internal sealed interface LocalConnectionSessionValidationState {
  data class Valid(val session: LocalAuthSession) : LocalConnectionSessionValidationState

  data object Invalid : LocalConnectionSessionValidationState
}

internal suspend fun validateLocalConnectionSession(): LocalConnectionSessionValidationState {
  val response =
      LocalUpstreamClientProvider.shared().get(localUcStatusUrl()) {
        header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
        header("X-Requested-With", "XMLHttpRequest")
      }
  if (response.status != HttpStatusCode.OK) {
    return LocalConnectionSessionValidationState.Invalid
  }

  val body = response.bodyAsText()
  if (!body.trimStart().startsWith("{")) {
    return LocalConnectionSessionValidationState.Invalid
  }

  val payload = localConnectionAuthJson.decodeFromString<UserInfoResponse>(body)
  val user = payload.data ?: return LocalConnectionSessionValidationState.Invalid
  if (payload.code != 0) {
    return LocalConnectionSessionValidationState.Invalid
  }

  val session =
      LocalAuthSession(
          username = user.schoolid ?: user.username ?: "",
          user = UserData(name = user.name.orEmpty(), schoolid = user.schoolid.orEmpty()),
          authenticatedAt = LocalAuthSessionStore.get()?.authenticatedAt ?: nowIsoString(),
          lastActivity = nowIsoString(),
      )
  LocalAuthSessionStore.save(session)
  return LocalConnectionSessionValidationState.Valid(session)
}

internal suspend fun resolveLocalBusinessAuthenticationFailure(
    fallbackCode: String,
    fallbackStatus: HttpStatusCode = HttpStatusCode.BadGateway,
): ApiCallException {
  val validation = runCatching { validateLocalConnectionSession() }.getOrNull()
  return if (validation == LocalConnectionSessionValidationState.Invalid) {
    clearLocalConnectionSession()
    localUnauthenticatedApiException()
  } else {
    ApiCallException(
        message = userFacingMessageForCode(fallbackCode, fallbackStatus),
        status = fallbackStatus,
        code = fallbackCode,
    )
  }
}

private suspend fun reportLocalLoginSuccess(username: String, successMode: LoginStatsSuccessMode) {
  val connectionMode =
      ConnectionRuntime.currentMode()?.takeIf { it != ConnectionMode.SERVER_RELAY }
          ?: ConnectionMode.DIRECT
  LoginStatsReporter.reportSuccess(username, successMode, connectionMode)
}

internal class LocalAuthServiceBackend : AuthServiceBackend {
  override fun hasPersistedSession(): Boolean = LocalAuthSessionStore.get() != null

  override fun applyStoredSession() = Unit

  override fun clearStoredSession() {
    clearLocalConnectionSession()
  }

  override suspend fun preloadLoginState(): Result<LoginPreloadResponse> {
    val noRedirectClient = LocalUpstreamClientProvider.newNoRedirectClient()
    return try {
      val response = noRedirectClient.get(loginUrl())
      if (response.status.value in 300..399) {
        activateUcLogin()
        return when (val validation = validateLocalConnectionSession()) {
          is LocalConnectionSessionValidationState.Valid -> {
            reportLocalLoginSuccess(
                validation.session.username.ifBlank { validation.session.user.schoolid },
                LoginStatsSuccessMode.PRELOAD_AUTO,
            )
            Result.success(
                LoginPreloadResponse(
                    captchaRequired = false,
                    userData = validation.session.user,
                )
            )
          }
          LocalConnectionSessionValidationState.Invalid ->
              Result.success(LoginPreloadResponse(captchaRequired = false))
        }
      }

      if (response.status != HttpStatusCode.OK) {
        return Result.success(LoginPreloadResponse(captchaRequired = false))
      }

      val loginPageHtml = response.bodyAsText()
      val execution = LocalCasParser.extractExecution(loginPageHtml).takeIf { it.isNotBlank() }
      val captchaInfo = LocalCasParser.detectCaptcha(loginPageHtml, captchaUrl())
      val hydratedCaptcha =
          captchaInfo?.let { info -> info.withBase64Image(fetchCaptchaImage(info.id)) }

      Result.success(
          LoginPreloadResponse(
              captchaRequired = hydratedCaptcha != null,
              captcha = hydratedCaptcha,
              execution = execution,
          )
      )
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("登录状态加载失败，请稍后重试"))
    } finally {
      noRedirectClient.close()
    }
  }

  override suspend fun login(
      username: String,
      password: String,
      captcha: String?,
      execution: String?,
  ): Result<LoginResponse> {
    val noRedirectClient = LocalUpstreamClientProvider.newNoRedirectClient()
    return try {
      val loginPageResponse = noRedirectClient.get(loginUrl())
      if (
          loginPageResponse.status != HttpStatusCode.OK &&
              loginPageResponse.status.value !in 300..399
      ) {
        return Result.failure(ApiCallException("登录失败，请稍后重试"))
      }

      if (loginPageResponse.status.value in 300..399) {
        activateUcLogin()
      } else {
        val loginPageHtml = loginPageResponse.bodyAsText()
        LocalCasParser.extractTipText(loginPageHtml)?.let { tip ->
          return Result.failure(ApiCallException(tip))
        }

        val actualExecution =
            execution?.takeIf { it.isNotBlank() } ?: LocalCasParser.extractExecution(loginPageHtml)
        val request =
            LoginRequest(
                username = username,
                password = password,
                captcha = captcha,
                execution = actualExecution,
            )
        val captchaInfo = LocalCasParser.detectCaptcha(loginPageHtml, captchaUrl())
        if (captchaInfo != null && captcha.isNullOrBlank()) {
          return Result.failure(
              CaptchaRequiredClientException(
                  captchaInfo.withBase64Image(fetchCaptchaImage(captchaInfo.id)),
                  actualExecution,
                  "需要验证码验证",
              )
          )
        }

        val parameters =
            if (captchaInfo != null || !captcha.isNullOrBlank()) {
              LocalCasParser.buildCaptchaLoginParameters(request, actualExecution)
            } else {
              LocalCasParser.buildCasLoginParameters(loginPageHtml, request)
            }
        val submitResponse =
            noRedirectClient.post(loginUrl()) { setBody(FormDataContent(parameters)) }
        followRedirectsAndCheckError(submitResponse, noRedirectClient)
        activateUcLogin()
      }

      when (val validation = validateLocalConnectionSession()) {
        is LocalConnectionSessionValidationState.Valid -> {
          reportLocalLoginSuccess(
              validation.session.username.ifBlank { validation.session.user.schoolid },
              LoginStatsSuccessMode.MANUAL,
          )
          Result.success(
              LoginResponse(
                  user = validation.session.user,
                  accessToken = "",
                  refreshToken = "",
                  accessTokenExpiresAt = "",
                  refreshTokenExpiresAt = "",
              )
          )
        }
        LocalConnectionSessionValidationState.Invalid ->
            Result.failure(
                ApiCallException(
                    message =
                        userFacingMessageForCode("unauthenticated", HttpStatusCode.Unauthorized),
                    status = HttpStatusCode.Unauthorized,
                    code = "unauthenticated",
                )
            )
      }
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("登录失败，请稍后重试"))
    } finally {
      noRedirectClient.close()
    }
  }

  override suspend fun getAuthStatus(): Result<SessionStatusResponse> {
    val storedSession =
        LocalAuthSessionStore.get()
            ?: return Result.failure(
                ApiCallException(
                    message =
                        userFacingMessageForCode("unauthenticated", HttpStatusCode.Unauthorized),
                    status = HttpStatusCode.Unauthorized,
                    code = "unauthenticated",
                )
            )

    return try {
      when (val validation = validateLocalConnectionSession()) {
        is LocalConnectionSessionValidationState.Valid -> {
          val refreshed = validation.session.copy(authenticatedAt = storedSession.authenticatedAt)
          LocalAuthSessionStore.save(refreshed)
          Result.success(
              SessionStatusResponse(
                  user = refreshed.user,
                  lastActivity = refreshed.lastActivity,
                  authenticatedAt = refreshed.authenticatedAt,
              )
          )
        }
        LocalConnectionSessionValidationState.Invalid -> {
          clearStoredSession()
          Result.failure(
              ApiCallException(
                  message =
                      userFacingMessageForCode("unauthenticated", HttpStatusCode.Unauthorized),
                  status = HttpStatusCode.Unauthorized,
                  code = "unauthenticated",
              )
          )
        }
      }
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("认证服务响应超时，请稍后重试"))
    }
  }

  override suspend fun logout(): Result<Unit> {
    return try {
      runCatching { LocalUpstreamClientProvider.shared().get(logoutUrl()) }
      clearStoredSession()
      Result.success(Unit)
    } catch (e: Exception) {
      clearStoredSession()
      Result.failure(e.toUserFacingApiException("注销时出现异常，本地登录状态已清除"))
    }
  }

  private suspend fun activateUcLogin() {
    LocalUpstreamClientProvider.shared().get(localUcActivateUrl())
  }

  @OptIn(ExperimentalEncodingApi::class)
  private suspend fun fetchCaptchaImage(captchaId: String): String? {
    val response = LocalUpstreamClientProvider.shared().get("${captchaUrl()}?captchaId=$captchaId")
    if (response.status != HttpStatusCode.OK) {
      return null
    }
    val bytes = response.body<ByteArray>()
    return "data:image/jpeg;base64,${Base64.encode(bytes)}"
  }

  private suspend fun followRedirectsAndCheckError(
      initialResponse: HttpResponse,
      noRedirectClient: HttpClient,
  ) {
    var currentResponse = initialResponse
    while (currentResponse.status.value in 300..399) {
      val location = currentResponse.headers[HttpHeaders.Location] ?: break
      currentResponse =
          noRedirectClient.get(resolveRedirectUrl(currentResponse.call.request.url, location))
    }

    val bodyText = runCatching { currentResponse.bodyAsText() }.getOrNull().orEmpty()
    val finalUrl = currentResponse.call.request.url.toString()
    if ("exception.message=" in finalUrl) {
      throw ApiCallException(finalUrl.substringAfter("exception.message=").substringBefore("&"))
    }
    val loginError =
        LocalCasParser.findLoginError(bodyText) ?: LocalCasParser.extractTipText(bodyText)
    if (currentResponse.status == HttpStatusCode.Unauthorized || !loginError.isNullOrBlank()) {
      throw ApiCallException(loginError ?: "账号或密码错误，请重试")
    }
    if (bodyText.contains("input name=\"execution\"")) {
      throw ApiCallException("账号或密码错误，请重试")
    }
  }

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
    val relativePath = "$basePath$separator$location"
    return "$authority$relativePath"
  }

  private fun loginUrl(): String = localUpstreamUrl("https://sso.buaa.edu.cn/login")

  private fun captchaUrl(): String = localUpstreamUrl("https://sso.buaa.edu.cn/captcha")

  private fun logoutUrl(): String = localUpstreamUrl("https://sso.buaa.edu.cn/logout")
}

private fun localUcStatusUrl(): String = localUpstreamUrl("https://uc.buaa.edu.cn/api/uc/status")

private fun localUcActivateUrl(): String =
    localUpstreamUrl(
        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
    )

internal class LocalUserServiceBackend : UserServiceBackend {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun getUserInfo(): Result<UserInfo> {
    return try {
      val response =
          LocalUpstreamClientProvider.shared()
              .get(localUpstreamUrl("https://uc.buaa.edu.cn/api/uc/userinfo"))
      val body = response.bodyAsText()
      if (isUcSessionExpired(response, body)) {
        clearLocalConnectionSession()
        return Result.failure(localUnauthenticatedApiException())
      }
      if (response.status != HttpStatusCode.OK) {
        return Result.failure(
            ApiCallException(
                message = userFacingMessageForCode("user_info_failed", response.status),
                status = response.status,
                code = "user_info_failed",
            )
        )
      }

      val payload = json.decodeFromString<UserInfoResponse>(body)
      val info = payload.data
      if (payload.code != 0 || info == null) {
        return Result.failure(
            ApiCallException(
                message =
                    userFacingMessageForCode(
                        "user_info_failed",
                        HttpStatusCode.InternalServerError,
                    ),
                status = HttpStatusCode.InternalServerError,
                code = "user_info_failed",
            )
        )
      }

      Result.success(info)
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("用户信息查询失败，请稍后重试"))
    }
  }

  private fun isUcSessionExpired(response: HttpResponse, body: String): Boolean {
    if (response.status == HttpStatusCode.Unauthorized) return true
    if (localIsSsoUrl(response.call.request.url.toString())) return true
    val trimmed = body.trimStart()
    return trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
        trimmed.startsWith("<html", ignoreCase = true) ||
        body.contains("input name=\"execution\"") ||
        body.contains("统一身份认证", ignoreCase = true)
  }
}

internal fun clearLocalConnectionSession() {
  LocalAuthSessionStore.clear()
  LocalCookieStore.clear()
  LocalUpstreamClientProvider.reset()
}

internal fun localUnauthenticatedApiException(): ApiCallException =
    ApiCallException(
        message = userFacingMessageForCode("unauthenticated", HttpStatusCode.Unauthorized),
        status = HttpStatusCode.Unauthorized,
        code = "unauthenticated",
    )

private fun nowIsoString(): String = Instant.fromEpochMilliseconds(nowMillis()).toString()

private fun nowMillis(): Long = GMTDate().timestamp

private fun CaptchaInfo.withBase64Image(encodedImage: String?): CaptchaInfo =
    copy(base64Image = encodedImage ?: base64Image)

internal object LocalCasParser {
  private val executionRegex =
      Regex(
          """<input[^>]*name=["']execution["'][^>]*value=["']([^"']+)["'][^>]*>""",
          RegexOption.IGNORE_CASE,
      )
  private val tipRegex =
      Regex(
          """<div[^>]*class=["'][^"']*tip-text[^"']*["'][^>]*>([\s\S]*?)</div>""",
          RegexOption.IGNORE_CASE,
      )
  private val captchaRegex =
      Regex("""config\.captcha\s*=\s*\{\s*type:\s*['"]([^'"]+)['"],\s*id:\s*['"]([^'"]+)['"]""")
  private val inputRegex = Regex("""<input\b([^>]*)>""", RegexOption.IGNORE_CASE)
  private val attrRegex = Regex("""([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*["']([^"']*)["']""")

  fun extractExecution(html: String): String =
      executionRegex.find(html)?.groupValues?.getOrNull(1).orEmpty()

  fun detectCaptcha(html: String, captchaUrlBase: String): CaptchaInfo? {
    val match = captchaRegex.find(html) ?: return null
    val type = match.groupValues[1]
    val id = match.groupValues[2]
    return CaptchaInfo(id = id, type = type, imageUrl = "$captchaUrlBase?captchaId=$id")
  }

  fun extractTipText(html: String): String? =
      tipRegex.find(html)?.groupValues?.getOrNull(1)?.stripHtml()?.trim()?.takeIf {
        it.isNotBlank()
      }

  fun findLoginError(html: String): String? {
    if (html.isBlank()) return null
    extractTipText(html)?.let {
      return it
    }
    val candidates =
        listOf(
            Regex(
                """<div[^>]*id=["']errorDiv["'][^>]*>([\s\S]*?)</div>""",
                RegexOption.IGNORE_CASE,
            ),
            Regex(
                """<div[^>]*class=["'][^"']*errors[^"']*["'][^>]*>([\s\S]*?)</div>""",
                RegexOption.IGNORE_CASE,
            ),
            Regex(
                """<p[^>]*class=["'][^"']*errors[^"']*["'][^>]*>([\s\S]*?)</p>""",
                RegexOption.IGNORE_CASE,
            ),
            Regex(
                """<span[^>]*class=["'][^"']*errors[^"']*["'][^>]*>([\s\S]*?)</span>""",
                RegexOption.IGNORE_CASE,
            ),
        )
    return candidates
        .asSequence()
        .mapNotNull { it.find(html)?.groupValues?.getOrNull(1)?.stripHtml()?.trim() }
        .firstOrNull { it.isNotBlank() }
  }

  fun buildCasLoginParameters(html: String, request: LoginRequest): io.ktor.http.Parameters {
    val inputs = inputRegex.findAll(html).map { parseAttributes(it.groupValues[1]) }.toList()
    val presentNames = mutableSetOf<String>()
    return io.ktor.http.Parameters.build {
      inputs.forEach { attrs ->
        val name = attrs["name"]?.trim().orEmpty()
        if (name.isBlank()) return@forEach
        val type = attrs["type"]?.trim()?.lowercase().orEmpty()
        val value = attrs["value"].orEmpty()
        when (name) {
          "username",
          "password" -> {
            presentNames += name
          }
          else -> {
            when (type) {
              "submit",
              "button",
              "image" -> Unit
              "checkbox" -> {
                presentNames += name
                if ("checked" in attrs) {
                  append(name, value.ifBlank { "on" })
                }
              }
              else -> {
                presentNames += name
                if (type == "hidden" || value.isNotBlank()) {
                  append(name, value)
                }
              }
            }
          }
        }
      }
      append("username", request.username)
      append("password", request.password)
      append("submit", "登录")
      request.captcha
          ?.takeIf { it.isNotBlank() }
          ?.let { captchaValue ->
            if (inputs.any { it["name"] == "captcha" }) append("captcha", captchaValue)
            if (inputs.any { it["name"] == "captchaResponse" })
                append("captchaResponse", captchaValue)
          }
      if (!presentNames.contains("_eventId")) append("_eventId", "submit")
      if (!presentNames.contains("execution")) append("execution", request.execution.orEmpty())
      if (!presentNames.contains("type")) append("type", "username_password")
    }
  }

  fun buildCaptchaLoginParameters(
      request: LoginRequest,
      execution: String = request.execution.orEmpty(),
  ): io.ktor.http.Parameters =
      io.ktor.http.Parameters.build {
        val captcha = request.captcha.orEmpty()
        append("username", request.username)
        append("password", request.password)
        append("captcha", captcha)
        append("captchaResponse", captcha)
        append("execution", execution)
        append("_eventId", "submit")
        append("submit", "登录")
        append("type", "username_password")
      }

  private fun parseAttributes(attributes: String): Map<String, String> {
    val values = linkedMapOf<String, String>()
    attrRegex.findAll(attributes).forEach { match ->
      values[match.groupValues[1]] = match.groupValues[2]
    }
    if (Regex("""\bchecked\b""", RegexOption.IGNORE_CASE).containsMatchIn(attributes)) {
      values["checked"] = "checked"
    }
    return values
  }

  private fun String.stripHtml(): String = replace(Regex("<[^>]+>"), " ")
}
