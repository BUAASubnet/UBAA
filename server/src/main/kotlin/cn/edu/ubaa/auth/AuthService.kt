package cn.edu.ubaa.auth

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
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
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

    val hasClientId = !request.clientId.isNullOrBlank()
    val hasExecution = !request.execution.isNullOrBlank()

    // 1. 尝试复用或准备会话环境
    if (!hasClientId && !hasExecution) {
      sessionManager.getSession(request.username, SessionManager.SessionAccess.READ_ONLY)?.let {
          existingSession ->
        val cachedUser = runCatching { verifySession(existingSession.client) }.getOrNull()
        if (cachedUser != null) {
          return refreshTokenService.issueLoginTokens(cachedUser, request.username)
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
              noRedirectClient.post(LOGIN_URL) { setBody(FormDataContent(loginFormParameters)) }

          followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient)
        } else {
          // 标准流程：先拉取登录页获取 execution
          val loginPageResponse = noRedirectClient.get(LOGIN_URL)
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
              val loginFormParameters = CasParser.buildCaptchaLoginParameters(request)
              val loginSubmitResponse =
                  noRedirectClient.post(LOGIN_URL) { setBody(FormDataContent(loginFormParameters)) }
              followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient)
            } else {
              val loginFormParameters = CasParser.buildCasLoginParameters(loginPageHtml, request)
              val loginSubmitResponse =
                  noRedirectClient.post(LOGIN_URL) { setBody(FormDataContent(loginFormParameters)) }
              followRedirectsAndCheckError(loginSubmitResponse, noRedirectClient)
            }
          }
        }
      }

      // 3. 激活相关子系统会话并验证（UC + BYXT 并行）
      client.get(
          VpnCipher.toVpnUrl(
              "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
          )
      )

      val userData: UserData?
      val byxtReady: Boolean
      coroutineScope {
        val byxtJob = async { ByxtService.initializeSession(client) }
        userData = verifySession(client)
        byxtReady = byxtJob.await()
      }

      if (userData != null && byxtReady) {
        sessionManager.commitSession(activeCandidate, userData)
        committed = true
        return refreshTokenService.issueLoginTokens(userData, activeCandidate.username)
      }
      failLogin("session verification failed or BYXT initialization failed")
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
        session.client.get(VpnCipher.toVpnUrl("https://sso.buaa.edu.cn/logout"))
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
        val loginPageResponse = noRedirectClient.get(LOGIN_URL)

        // 检测自动登录（已在 SSO 登录）
        if (loginPageResponse.status.value in 300..399) {
          client.get(
              VpnCipher.toVpnUrl(
                  "https://uc.buaa.edu.cn/api/login?target=https%3A%2F%2Fuc.buaa.edu.cn%2F%23%2Fuser%2Flogin"
              )
          )

          val userData: UserData?
          val byxtReady: Boolean
          coroutineScope {
            val byxtJob = async { ByxtService.initializeSession(client) }
            userData = verifySession(client)
            byxtReady = byxtJob.await()
          }

          if (userData != null && byxtReady && !userData.schoolid.isNullOrBlank()) {
            val sessionCandidate =
                sessionManager.promotePreLoginSession(clientId, userData.schoolid)
            if (sessionCandidate != null) {
              sessionManager.commitSession(sessionCandidate, userData)
              val tokenResponse = refreshTokenService.issueTokens(sessionCandidate.username)
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
        client.get(VpnCipher.toVpnUrl(UC_STATUS_URL)) {
          header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
          header("X-Requested-With", "XMLHttpRequest")
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
      val response = client.get("$CAPTCHA_URL_BASE?captchaId=$captchaId")
      if (response.status == HttpStatusCode.OK) response.body<ByteArray>() else null
    } catch (e: Exception) {
      null
    }
  }

  suspend fun refreshTokens(refreshToken: String): TokenRefreshResponse? =
      refreshTokenService.refreshTokens(refreshToken, sessionManager)

  suspend fun validateSession(session: SessionManager.UserSession): Boolean {
    val userData: UserData?
    val byxtReady: Boolean
    coroutineScope {
      val byxtJob = async { ByxtService.initializeSession(session.client) }
      userData = verifySession(session.client)
      byxtReady = byxtJob.await()
    }
    return userData != null && byxtReady
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
