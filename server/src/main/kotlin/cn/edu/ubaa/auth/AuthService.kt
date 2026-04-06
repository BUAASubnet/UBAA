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
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.HttpClient
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.client.request.forms.*
import io.ktor.client.statement.*
import io.ktor.http.*
import kotlin.time.Duration
import kotlin.time.TimeSource
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
) {

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

    val hasClientId = !request.clientId.isNullOrBlank()
    val hasExecution = !request.execution.isNullOrBlank()

    // 1. 尝试复用或准备会话环境
    if (!hasClientId && !hasExecution) {
      sessionManager.getSession(request.username, SessionManager.SessionAccess.READ_ONLY)?.let {
          existingSession ->
        val cachedUser =
            timeline.measure("ucVerify") {
              runCatching { verifySession(existingSession.client) }.getOrNull()
            }
        if (cachedUser != null) {
          timeline
              .measure("issueTokens") {
                maybeWarmupPortal(existingSession)
                refreshTokenService.issueLoginTokens(cachedUser, request.username)
              }
              .also {
                timeline.logSuccess("reused_session")
                return it
              }
        }
        sessionManager.invalidateSession(request.username)
      }
    }

    var sessionCandidate: SessionManager.SessionCandidate? = null
    var committed = false

    try {
      sessionCandidate =
          if (hasClientId) {
            sessionManager.promotePreLoginSession(request.clientId!!, request.username)
                ?: run {
                  sessionManager.invalidateSession(request.username)
                  sessionManager.prepareSession(request.username)
                }
          } else {
            sessionManager.invalidateSession(request.username)
            sessionManager.prepareSession(request.username)
          }

      val activeCandidate = requireNotNull(sessionCandidate)
      val client = activeCandidate.client

      withNoRedirectClient(client) { noRedirectClient ->
        // 2. 提交登录表单
        if (hasExecution) {
          // 直接提交（来自客户端的 preload 结果）
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
          // 标准流程：先拉取登录页获取 execution
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
              // 需要验证码但请求中未提供，则抛出异常让客户端处理
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

      // 3. 激活 UC 并验证核心会话（不再同步等待教务门户探活）
      timeline.measure("activateUc") {
        AppObservability.observeUpstreamRequest("uc", "activate_login") {
          client.get(
              VpnCipher.toVpnUrl(
                  "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
              )
          )
        }
      }

      val userData = timeline.measure("ucVerify") { verifySession(client) }

      if (userData != null) {
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
      failLogin("core session verification failed")
    } catch (e: Exception) {
      timeline.logFailure(e)
      throw e
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
    val preLoginCandidate = sessionManager.preparePreLoginSession(clientId)
    val client = preLoginCandidate.client

    return try {
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

          val userData = verifySession(client)

          if (userData != null && !userData.schoolid.isNullOrBlank()) {
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
      }
    } catch (e: Exception) {
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

  /** 访问状态接口验证当前客户端是否已成功认证。 */
  private suspend fun verifySession(client: HttpClient): UserData? {
    val statusResponse =
        AppObservability.observeUpstreamRequest("uc", "fetch_uc_user") {
          client.get(VpnCipher.toVpnUrl(UC_STATUS_URL)) {
            header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
            header("X-Requested-With", "XMLHttpRequest")
          }
        }
    if (statusResponse.status != HttpStatusCode.OK) return null
    val body = statusResponse.bodyAsText()
    if (!body.trimStart().startsWith("{")) return null

    return try {
      val resp = Json.decodeFromString<UserInfoResponse>(body)
      val data = resp.data
      if (resp.code == 0 && data != null) {
        UserData(name = data.name.orEmpty(), schoolid = data.schoolid.orEmpty())
      } else {
        log.warn("Verify session response code not 0: {}", resp.code)
        null
      }
    } catch (e: Exception) {
      log.warn("Verify session failed: {}", e.message)
      null
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

  suspend fun validateSession(session: SessionManager.UserSession): Boolean {
    val userData = verifySession(session.client)
    if (userData != null) {
      maybeWarmupPortal(session)
      return true
    }
    return false
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
