package cn.edu.ubaa.auth

import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.metrics.LoginMetricsSink
import cn.edu.ubaa.metrics.LoginSuccessMode
import cn.edu.ubaa.metrics.NoOpLoginMetricsSink
import cn.edu.ubaa.model.dto.LoginPreloadResponse
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.model.dto.LoginResponse
import cn.edu.ubaa.model.dto.TokenRefreshResponse
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.dto.UserInfoResponse
import cn.edu.ubaa.utils.UpstreamTimeoutException
import cn.edu.ubaa.utils.VpnCipher
import cn.edu.ubaa.utils.withUpstreamDeadline
import io.ktor.client.HttpClient
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.TimeSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import org.slf4j.LoggerFactory

/**
 * 后端认证服务核心类。 处理复杂的 BUAA SSO 登录逻辑，包括多重重定向、验证码识别、会话持久化及 JWT 签发。
 *
 * @property sessionManager 负责隔离用户会话和存储 Cookie 的管理器。
 */
class AuthService(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val refreshTokenService: RefreshTokenService = GlobalRefreshTokenService.instance,
    private val loginMetricsSink: LoginMetricsSink = NoOpLoginMetricsSink,
    private val portalWarmupCoordinator: AcademicPortalWarmupCoordinator =
        GlobalAcademicPortalWarmupCoordinator.instance,
    private val distributedLockManager: DistributedLockManager = NoOpDistributedLockManager,
) {
  internal sealed interface SessionValidationResult {
    data class Valid(val userData: UserData) : SessionValidationResult

    data object Invalid : SessionValidationResult

    sealed interface RetryableFailure : SessionValidationResult {
      val cause: Throwable?
    }

    data class Timeout(override val cause: Throwable? = null) : RetryableFailure

    data class Error(override val cause: Throwable? = null) : RetryableFailure
  }

  private data class SessionValidationKey(
      val subject: String,
      val client: HttpClient,
  )

  internal fun interface DerivedClientFactory {
    fun create(baseClient: HttpClient): DerivedClientHandle
  }

  internal interface DerivedClientHandle {
    val client: HttpClient

    fun close()
  }

  private class ConfiguredDerivedClientHandle(baseClient: HttpClient) : DerivedClientHandle {
    override val client: HttpClient = baseClient.config { followRedirects = false }

    override fun close() {
      client.close()
    }
  }

  private val log = LoggerFactory.getLogger(AuthService::class.java)
  private val GENERIC_LOGIN_ERROR = "出了点问题，请检查用户名和密码，或稍后重试"
  private val loginMutexes = ConcurrentHashMap<String, Mutex>()
  private val validationRequests =
      ConcurrentHashMap<SessionValidationKey, CompletableDeferred<SessionValidationResult>>()
  private val freshLoginBulkhead = Semaphore(AuthConfig.loginMaxConcurrency)
  internal var derivedClientFactory: DerivedClientFactory = DerivedClientFactory { baseClient ->
    ConfiguredDerivedClientHandle(baseClient)
  }

  /** 统一抛出登录失败异常。 */
  private fun failLogin(reason: String? = null): Nothing {
    reason?.let { log.warn("Login failed detail: {}", it) }
    throw LoginException(GENERIC_LOGIN_ERROR)
  }

  /**
   * 执行登录流程并返回用户信息及访问令牌对。 支持从 preload 会话升级，或直接启动新会话。
   *
   * @param request 包含凭据和环境信息的登录请求。
   * @return 登录结果 LoginResponse。
   * @throws LoginException 凭据错误。
   * @throws CaptchaRequiredException 需提供验证码。
   */
  suspend fun login(request: LoginRequest): LoginResponse {
    log.info("Starting login process for user: {}", request.username)
    val timeline = LoginTimeline(request.username, log)
    return withUserLoginMutex(request.username) {
      try {
        if (request.execution.isNullOrBlank() && request.clientId.isNullOrBlank()) {
          tryReuseCommittedSession(request, timeline)?.let { reusedResponse ->
            AppObservability.recordLoginFlowEvent("login_reuse_hit")
            timeline.logSuccess("reused_session")
            return@withUserLoginMutex reusedResponse
          }
        }

        withFreshLoginPermit {
          distributedLockManager.withLock("auth_login", request.username) {
            if (request.execution.isNullOrBlank() && request.clientId.isNullOrBlank()) {
              tryReuseCommittedSession(request, timeline)?.let { reusedResponse ->
                AppObservability.recordLoginFlowEvent("login_reuse_after_lock")
                timeline.logSuccess("reused_session_after_lock")
                return@withLock reusedResponse
              }
            }

            withUpstreamDeadline(
                AuthConfig.loginTimeoutMillis.milliseconds,
                "认证服务响应超时，请稍后重试",
                "auth_upstream_timeout",
            ) {
              performFreshLogin(request, timeline)
            }
          }
        }
      } catch (e: Exception) {
        timeline.logFailure(e)
        throw e
      }
    }
  }

  /** 注销用户。 通知 SSO 并清理本地所有关联会话。 */
  suspend fun logout(username: String) {
    val session = sessionManager.getSession(username, SessionManager.SessionAccess.READ_ONLY)
    if (session != null) {
      try {
        AppObservability.observeUpstreamRequest("sso", "logout") {
          session.client.get(VpnCipher.toVpnUrl("https://sso.buaa.edu.cn/logout"))
        }
      } catch (e: Exception) {
        log.warn("Error calling SSO logout: {}", e.message)
      }
    }
    refreshTokenService.invalidate(username)
    sessionManager.invalidateSession(username)
  }

  /**
   * 登录预加载逻辑。 检测 SSO 是否已登录（自动登录），或返回登录所需的验证码信息。
   *
   * @param clientId 客户端 ID。
   * @return 预加载结果。
   */
  suspend fun preloadLoginState(clientId: String): LoginPreloadResponse {
    require(clientId.isNotBlank()) { "clientId is required" }
    return try {
      distributedLockManager.withLock("auth_prelogin", clientId) {
        val preLoginCandidate = sessionManager.preparePreLoginSession(clientId)
        val client = preLoginCandidate.client

        withUpstreamDeadline(
            AuthConfig.preloadTimeoutMillis.milliseconds,
            "登录状态加载超时，请稍后重试",
            "auth_upstream_timeout",
        ) {
          withNoRedirectClient(client) { noRedirectClient ->
            val loginPageResponse =
                AppObservability.observeUpstreamRequest("sso", "preload_sso_check") {
                  noRedirectClient.get(LOGIN_URL)
                }

            // 检测自动登录（已在 SSO 登录）
            if (loginPageResponse.status.value in 300..399) {
              AppObservability.observeUpstreamRequest("uc", "activate_login") {
                client.get(
                    VpnCipher.toVpnUrl(
                        "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
                    )
                )
              }
              sessionManager.persistPreLoginSession(clientId)

              when (
                  val validationResult =
                      validateSession("preload:$clientId", client, recordShared = false)
              ) {
                is SessionValidationResult.Valid -> {
                  val userData = validationResult.userData
                  if (!userData.schoolid.isNullOrBlank()) {
                    val sessionCandidate =
                        sessionManager.promotePreLoginSession(clientId, userData.schoolid)
                    if (sessionCandidate != null) {
                      val committedSession = sessionManager.commitSession(sessionCandidate, userData)
                      val tokenResponse = refreshTokenService.issueTokens(sessionCandidate.username)
                      safeRecordLoginSuccess(
                          userData.schoolid.ifBlank { sessionCandidate.username },
                          LoginSuccessMode.PRELOAD_AUTO,
                      )
                      maybeWarmupPortal(committedSession)
                      return@withNoRedirectClient LoginPreloadResponse(
                          captchaRequired = false,
                          clientId = clientId,
                          accessToken = tokenResponse.accessToken,
                          refreshToken = tokenResponse.refreshToken,
                          accessTokenExpiresAt = tokenResponse.accessTokenExpiresAt,
                          refreshTokenExpiresAt = tokenResponse.refreshTokenExpiresAt,
                          userData = userData,
                      )
                    }
                  }
                }
                SessionValidationResult.Invalid ->
                    return@withNoRedirectClient LoginPreloadResponse(
                        captchaRequired = false,
                        clientId = clientId,
                    )
                is SessionValidationResult.RetryableFailure ->
                    throw authUpstreamTimeout(validationResult.cause)
              }

              return@withNoRedirectClient LoginPreloadResponse(
                  captchaRequired = false,
                  clientId = clientId,
              )
            }

            if (loginPageResponse.status != HttpStatusCode.OK)
                return@withNoRedirectClient LoginPreloadResponse(
                    captchaRequired = false,
                    clientId = clientId,
                )

            val loginPageHtml = loginPageResponse.bodyAsText()
            val execution = CasParser.extractExecution(loginPageHtml)
            val captchaInfo = CasParser.detectCaptcha(loginPageHtml, CAPTCHA_URL_BASE)

            val response =
                if (captchaInfo != null) {
                  val captchaImageBytes = getCaptchaImage(client, captchaInfo.id)
                  val base64Image =
                      captchaImageBytes?.let {
                        "data:image/jpeg;base64," + java.util.Base64.getEncoder().encodeToString(it)
                      }
                  LoginPreloadResponse(
                      captchaRequired = true,
                      captcha = captchaInfo.copy(base64Image = base64Image),
                      execution = execution,
                      clientId = clientId,
                  )
                } else {
                  LoginPreloadResponse(
                      captchaRequired = false,
                      execution = execution.takeIf { it.isNotBlank() },
                      clientId = clientId,
                  )
                }
            sessionManager.persistPreLoginSession(clientId)
            response
          }
        }
      }
    } catch (e: UpstreamTimeoutException) {
      AppObservability.recordAuthPreloadResult("degraded_timeout")
      sessionManager.cleanupPreLoginSession(clientId)
      LoginPreloadResponse(captchaRequired = false, clientId = clientId)
    } catch (e: Exception) {
      AppObservability.recordAuthPreloadResult("degraded_error")
      sessionManager.cleanupPreLoginSession(clientId)
      LoginPreloadResponse(captchaRequired = false, clientId = clientId)
    }
  }

  internal suspend fun <T> withNoRedirectClient(
      baseClient: HttpClient,
      block: suspend (HttpClient) -> T,
  ): T {
    val derivedClient = derivedClientFactory.create(baseClient)
    return try {
      block(derivedClient.client)
    } finally {
      derivedClient.close()
    }
  }

  companion object {
    private val LOGIN_URL = VpnCipher.toVpnUrl("https://sso.buaa.edu.cn/login")
    private val UC_STATUS_URL = "https://uc.buaa.edu.cn/api/uc/status"
    private val CAPTCHA_URL_BASE = VpnCipher.toVpnUrl("https://sso.buaa.edu.cn/captcha")
  }

  /** 获取验证码图片的字节数组。 */
  suspend fun getCaptchaImage(client: HttpClient, captchaId: String): ByteArray? {
    return try {
      val response =
          AppObservability.observeUpstreamRequest("sso", "captcha_fetch") {
            client.get("$CAPTCHA_URL_BASE?captchaId=$captchaId")
          }
      if (response.status == HttpStatusCode.OK) response.body<ByteArray>() else null
    } catch (e: Exception) {
      null
    }
  }

  suspend fun refreshTokens(refreshToken: String): TokenRefreshResponse? =
      refreshTokenService.refreshTokens(refreshToken, sessionManager)

  internal suspend fun validateSession(
      session: SessionManager.UserSession
  ): SessionValidationResult {
    val validationResult = validateSession(session.username, session.client)
    if (validationResult is SessionValidationResult.Valid) {
      maybeWarmupPortal(session)
    }
    return validationResult
  }

  private suspend fun safeRecordLoginSuccess(username: String, mode: LoginSuccessMode) {
    try {
      loginMetricsSink.recordSuccess(username, mode)
    } catch (e: Exception) {
      log.warn("Failed to record login metrics for user {}", username, e)
    }
  }

  private fun maybeWarmupPortal(session: SessionManager.UserSession) {
    if (session.portalType == AcademicPortalType.UNKNOWN) {
      portalWarmupCoordinator.warmup(session.username, session.client)
    }
  }

  private suspend fun tryReuseCommittedSession(
      request: LoginRequest,
      timeline: LoginTimeline,
  ): LoginResponse? {
    val existingSession =
        sessionManager.getSession(request.username, SessionManager.SessionAccess.READ_ONLY)
            ?: return null
    return when (
        val validationResult =
            timeline.measure("ucVerify") {
              validateSession(existingSession.username, existingSession.client)
            }
    ) {
      is SessionValidationResult.Valid ->
          timeline.measure("issueTokens") {
            maybeWarmupPortal(existingSession)
            refreshTokenService.issueLoginTokens(validationResult.userData, request.username)
          }
      SessionValidationResult.Invalid -> {
        sessionManager.invalidateSession(request.username)
        null
      }
      is SessionValidationResult.RetryableFailure -> authUpstreamTimeout(validationResult.cause)
    }
  }

  private suspend fun performFreshLogin(
      request: LoginRequest,
      timeline: LoginTimeline,
  ): LoginResponse {
    val hasClientId = !request.clientId.isNullOrBlank()
    val hasExecution = !request.execution.isNullOrBlank()

    var sessionCandidate: SessionManager.SessionCandidate? = null
    var committed = false

    try {
      sessionCandidate =
          if (hasClientId && hasExecution) {
            distributedLockManager.withLock("auth_prelogin", request.clientId!!) {
              sessionManager.promotePreLoginSession(request.clientId!!, request.username)
                  ?: run {
                    AppObservability.recordLoginFlowEvent("login_prelogin_miss")
                    sessionManager.prepareSession(request.username)
                  }
            }
          } else {
            sessionManager.prepareSession(request.username)
          }

      val activeCandidate = requireNotNull(sessionCandidate)
      val client = activeCandidate.client

      withNoRedirectClient(client) { noRedirectClient ->
        if (hasExecution) {
          val execution = request.execution!!
          val loginFormParameters =
              if (!request.captcha.isNullOrBlank()) {
                CasParser.buildCaptchaLoginParameters(request)
              } else {
                CasParser.buildDefaultParameters(request, execution)
              }

          val loginSubmitResponse =
              timeline.measure("submitCas") {
                AppObservability.observeUpstreamRequest("sso", "submit_credentials") {
                  noRedirectClient.post(LOGIN_URL) { setBody(FormDataContent(loginFormParameters)) }
                }
              }

          followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient)
        } else {
          val loginPageResponse =
              timeline.measure("loadLoginPage") {
                AppObservability.observeUpstreamRequest("sso", "load_login_page") {
                  noRedirectClient.get(LOGIN_URL)
                }
              }
          if (
              !loginPageResponse.status.isSuccess() &&
                  loginPageResponse.status != HttpStatusCode.Found
          ) {
            failLogin("load login page status=" + loginPageResponse.status)
          }
          val loginPageHtml = loginPageResponse.bodyAsText()

          CasParser.extractTipText(loginPageHtml)?.let { tip -> failLogin(tip) }

          val execution = CasParser.extractExecution(loginPageHtml)
          if (execution.isNotBlank()) {
            val captchaInfo = CasParser.detectCaptcha(loginPageHtml, CAPTCHA_URL_BASE)
            if (captchaInfo != null) {
              if (request.captcha.isNullOrBlank()) {
                val captchaImageBytes = getCaptchaImage(client, captchaInfo.id)
                val base64Image =
                    captchaImageBytes?.let {
                      "data:image/jpeg;base64," + java.util.Base64.getEncoder().encodeToString(it)
                    }
                throw CaptchaRequiredException(
                    captchaInfo.copy(base64Image = base64Image),
                    execution,
                )
              }
              val loginFormParameters =
                  CasParser.buildCasLoginParameters(
                      loginPageHtml,
                      request.copy(execution = execution),
                  )
              val loginSubmitResponse =
                  timeline.measure("submitCas") {
                    AppObservability.observeUpstreamRequest("sso", "submit_credentials") {
                      noRedirectClient.post(LOGIN_URL) {
                        setBody(FormDataContent(loginFormParameters))
                      }
                    }
                  }
              followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient)
            } else {
              val loginFormParameters = CasParser.buildCasLoginParameters(loginPageHtml, request)
              val loginSubmitResponse =
                  timeline.measure("submitCas") {
                    AppObservability.observeUpstreamRequest("sso", "submit_credentials") {
                      noRedirectClient.post(LOGIN_URL) {
                        setBody(FormDataContent(loginFormParameters))
                      }
                    }
                  }
              followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient)
            }
          }
        }
      }

      timeline.measure("activateUc") {
        AppObservability.observeUpstreamRequest("uc", "activate_login") {
          client.get(
              VpnCipher.toVpnUrl(
                  "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
              )
          )
        }
      }

      when (
          val validationResult =
              timeline.measure("ucVerify") {
                validateSession(activeCandidate.username, client, recordShared = false)
              }
      ) {
        is SessionValidationResult.Valid -> {
          val userData = validationResult.userData
          val committedSession =
              timeline.measure("commitSession") {
                sessionManager.commitSession(activeCandidate, userData)
              }
          committed = true
          val response =
              timeline.measure("issueTokens") {
                refreshTokenService.issueLoginTokens(userData, activeCandidate.username)
              }
          safeRecordLoginSuccess(
              userData.schoolid.ifBlank { activeCandidate.username },
              LoginSuccessMode.MANUAL,
          )
          timeline.measure("portalWarmupAsync") { maybeWarmupPortal(committedSession) }
          timeline.logSuccess("manual")
          return response
        }
        SessionValidationResult.Invalid -> failLogin("core session verification failed")
        is SessionValidationResult.RetryableFailure -> authUpstreamTimeout(validationResult.cause)
      }
    } finally {
      if (!committed) {
        sessionCandidate?.let {
          log.debug("Disposing incomplete session candidate for user: {}", it.username)
          runCatching { sessionManager.disposeSessionCandidate(it) }
              .onFailure { disposeError ->
                log.warn(
                    "Failed to dispose incomplete session candidate for user: {}",
                    it.username,
                    disposeError,
                )
              }
        }
      }
    }
  }

  private suspend fun <T> withUserLoginMutex(username: String, block: suspend () -> T): T {
    val mutex = loginMutexes.computeIfAbsent(username) { Mutex() }
    val acquiredImmediately = mutex.tryLock()
    if (!acquiredImmediately) {
      AppObservability.recordLoginFlowEvent("login_mutex_wait")
      mutex.lock()
    }
    try {
      return block()
    } finally {
      mutex.unlock()
      if (!mutex.isLocked) {
        loginMutexes.remove(username, mutex)
      }
    }
  }

  private suspend fun <T> withFreshLoginPermit(block: suspend () -> T): T {
    val acquiredImmediately = freshLoginBulkhead.tryAcquire()
    if (!acquiredImmediately) {
      AppObservability.recordLoginFlowEvent("login_bulkhead_wait")
      freshLoginBulkhead.acquire()
    }
    try {
      return block()
    } finally {
      freshLoginBulkhead.release()
    }
  }

  private suspend fun validateSession(
      subject: String,
      client: HttpClient,
      recordShared: Boolean = true,
  ): SessionValidationResult {
    val key = SessionValidationKey(subject, client)
    validationRequests[key]?.let { shared ->
      if (recordShared) {
        AppObservability.recordAuthValidationResult("shared")
      }
      return shared.await()
    }

    val deferred = CompletableDeferred<SessionValidationResult>()
    val existing = validationRequests.putIfAbsent(key, deferred)
    if (existing != null) {
      if (recordShared) {
        AppObservability.recordAuthValidationResult("shared")
      }
      return existing.await()
    }

    try {
      val result = performSessionValidation(client)
      deferred.complete(result)
      return result
    } catch (e: CancellationException) {
      deferred.completeExceptionally(e)
      throw e
    } catch (e: Throwable) {
      deferred.completeExceptionally(e)
      throw e
    } finally {
      validationRequests.remove(key, deferred)
    }
  }

  private suspend fun performSessionValidation(client: HttpClient): SessionValidationResult {
    return try {
      val validationResult =
          withUpstreamDeadline(
              AuthConfig.validationTimeoutMillis.milliseconds,
              "认证服务响应超时，请稍后重试",
              "auth_upstream_timeout",
          ) {
            val statusResponse =
                AppObservability.observeUpstreamRequest("uc", "fetch_uc_user") {
                  client.get(VpnCipher.toVpnUrl(UC_STATUS_URL)) {
                    header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
                    header("X-Requested-With", "XMLHttpRequest")
                  }
                }
            if (statusResponse.status != HttpStatusCode.OK) {
              return@withUpstreamDeadline SessionValidationResult.Invalid
            }

            val body = statusResponse.bodyAsText()
            if (!body.trimStart().startsWith("{")) {
              return@withUpstreamDeadline SessionValidationResult.Invalid
            }

            val resp = Json.decodeFromString<UserInfoResponse>(body)
            val data = resp.data
            if (resp.code == 0 && data != null) {
              SessionValidationResult.Valid(
                  UserData(name = data.name.orEmpty(), schoolid = data.schoolid.orEmpty())
              )
            } else {
              log.warn("Verify session response code not 0: {}", resp.code)
              SessionValidationResult.Invalid
            }
          }
      when (validationResult) {
        is SessionValidationResult.Valid -> AppObservability.recordAuthValidationResult("success")
        SessionValidationResult.Invalid -> AppObservability.recordAuthValidationResult("invalid")
        is SessionValidationResult.RetryableFailure -> Unit
      }
      validationResult
    } catch (e: UpstreamTimeoutException) {
      AppObservability.recordAuthValidationResult("timeout")
      SessionValidationResult.Timeout(e)
    } catch (e: CancellationException) {
      throw e
    } catch (e: Exception) {
      AppObservability.recordAuthValidationResult("error")
      log.warn("Verify session failed: {}", e.message)
      SessionValidationResult.Error(e)
    }
  }

  private fun authUpstreamTimeout(cause: Throwable? = null): Nothing {
    throw UpstreamTimeoutException("认证服务响应超时，请稍后重试", "auth_upstream_timeout", cause)
  }

  /**
   * 跟随 SSO 流程中的所有重定向，并检测是否存在错误提示或依然停留在登录页。
   *
   * @param initialResponse 初始 HTTP 响应。
   * @param noRedirectClient 配置为不跟随重定向的 HttpClient。
   * @return 最终的 HTTP 响应。
   * @throws LoginException 当检测到登录失败、凭据错误或异常信息时抛出。
   */
  private suspend fun followRedirectsAndCheckError(
      initialResponse: HttpResponse,
      noRedirectClient: HttpClient,
  ): HttpResponse {
    var currentResponse = initialResponse
    log.debug("Following redirects starting from: {}", initialResponse.request.url)
    while (currentResponse.status.value in 300..399) {
      val location = currentResponse.headers[HttpHeaders.Location] ?: break
      val nextUrl =
          try {
            val base = java.net.URI.create(currentResponse.request.url.toString())
            base.resolve(location).toURL().toString()
          } catch (e: Exception) {
            location
          }
      log.debug("Redirecting to: {}", nextUrl)
      currentResponse = noRedirectClient.get(nextUrl)
    }

    val bodyText = runCatching { currentResponse.bodyAsText() }.getOrNull() ?: ""
    val url = currentResponse.request.url.toString()

    if (url.contains("exception.message=")) {
      failLogin(url.substringAfter("exception.message=").decodeURLQueryComponent())
    }
    if (
        currentResponse.status == HttpStatusCode.Unauthorized ||
            CasParser.findLoginError(bodyText) != null
    ) {
      failLogin(CasParser.findLoginError(bodyText) ?: CasParser.extractTipText(bodyText))
    }
    if (bodyText.contains("input name=\"execution\"")) {
      failLogin("账号或密码错误")
    }
    return currentResponse
  }
}

private class LoginTimeline(
    private val username: String,
    private val log: org.slf4j.Logger,
) {
  private val startMark = TimeSource.Monotonic.markNow()
  private val stages = linkedMapOf<String, Duration>()

  suspend fun <T> measure(stage: String, block: suspend () -> T): T {
    val mark = TimeSource.Monotonic.markNow()
    return block().also { stages[stage] = mark.elapsedNow() }
  }

  fun logSuccess(mode: String) {
    log.info(
        "Login timeline user={} mode={} total={} {}",
        username,
        mode,
        startMark.elapsedNow().inWholeMilliseconds,
        stageSummary(),
    )
  }

  fun logFailure(error: Exception) {
    log.warn(
        "Login timeline user={} failed={} total={} {}",
        username,
        error::class.simpleName ?: "unknown",
        startMark.elapsedNow().inWholeMilliseconds,
        stageSummary(),
    )
  }

  private fun stageSummary(): String {
    return if (stages.isEmpty()) {
      "stages=none"
    } else {
      stages.entries.joinToString(prefix = "stages=") { (name, duration) ->
        "$name=${duration.inWholeMilliseconds}ms"
      }
    }
  }
}
