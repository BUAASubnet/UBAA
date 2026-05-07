package cn.edu.ubaa.judge

import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.engine.cio.endpoint
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.Cookie
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.util.date.GMTDate
import java.net.URI
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.slf4j.LoggerFactory

/** 希冀原始客户端。负责基于已登录的 SSO 会话访问 judge.buaa.edu.cn。 */
internal open class JudgeClient(
    private val username: String,
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val ownedClient: HttpClient? = null,
) {
  private val log = LoggerFactory.getLogger(JudgeClient::class.java)
  private val courseSelectionMutex = Mutex()
  private val sessionActivationMutex = Mutex()
  @Volatile private var judgeSessionActivated = false

  open suspend fun getCourses(): List<JudgeCourseRaw> {
    ensureJudgeSession()
    val body = getHtml("get_courses", "$BASE_URL/courselist.jsp?courseID=0")
    return JudgeParsers.parseCourses(body)
  }

  open suspend fun getAssignments(course: JudgeCourseRaw): List<JudgeAssignmentRaw> {
    ensureJudgeSession()
    return courseSelectionMutex.withLock {
      selectCourse(course.courseId)
      val body = getHtml("get_assignments", "$BASE_URL/assignment/index.jsp")
      JudgeParsers.parseAssignments(body, course)
    }
  }

  open suspend fun getAssignmentDetail(
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
  ): JudgeAssignmentParsedDetail {
    ensureJudgeSession()
    return courseSelectionMutex.withLock {
      selectCourse(courseId)
      val body =
          getHtml("get_assignment_detail", "$BASE_URL/assignment/index.jsp?assignID=$assignmentId")
      JudgeParsers.parseAssignmentDetail(
          html = body,
          courseId = courseId,
          courseName = courseName,
          assignmentId = assignmentId,
          title = title,
      )
    }
  }

  open fun close() {
    ownedClient?.close()
  }

  open suspend fun <T> withIsolatedClient(block: suspend (JudgeClient) -> T): T {
    val session = sessionManager.requireSession(username)
    val workerClient = buildJudgeWorkerClient(ForkedJudgeCookieStorage(session.cookieStorage))
    val worker =
        JudgeClient(
            username = username,
            sessionManager = sessionManager,
            ownedClient = workerClient,
        )
    return try {
      block(worker)
    } finally {
      worker.close()
    }
  }

  private suspend fun selectCourse(courseId: String) {
    getHtml("select_course", "$BASE_URL/courselist.jsp?courseID=$courseId")
  }

  private suspend fun ensureJudgeSession(forceRefresh: Boolean = false) {
    if (!forceRefresh && judgeSessionActivated) return
    sessionActivationMutex.withLock {
      if (!forceRefresh && judgeSessionActivated) return@withLock
      val client = httpClient()
      val activationResponse =
          AppObservability.observeUpstreamRequest("judge", "activate_login") {
            client.get(normalizeUrl(JUDGE_SERVICE_LOGIN_URL)) { applyJudgeBrowserHeaders() }
          }
      val response = followRedirectIfNeeded(client, "activate_redirect", activationResponse)
      val body = response.bodyAsText()
      if (isSessionExpired(response, body)) {
        log.info("Judge service activation requires fresh SSO login for user {}", username)
        throw JudgeAuthenticationException("希冀登录状态异常，请重新登录后重试")
      }
      if (response.status != HttpStatusCode.OK) {
        throw JudgeException("希冀服务暂时不可用，请稍后重试")
      }
      judgeSessionActivated = true
    }
  }

  private suspend fun followRedirectIfNeeded(
      client: HttpClient,
      operation: String,
      response: HttpResponse,
  ): HttpResponse {
    if (response.status.value !in 300..399) return response
    val location =
        response.headers[HttpHeaders.Location]?.takeIf { it.isNotBlank() } ?: return response
    val redirectUrl = resolveRedirectUrl(response.call.request.url.toString(), location)
    return AppObservability.observeUpstreamRequest("judge", operation) {
      client.get(normalizeUrl(redirectUrl)) { applyJudgeBrowserHeaders() }
    }
  }

  private suspend fun getHtml(
      operation: String,
      url: String,
      retry: Int = DEFAULT_RETRY_COUNT,
  ): String {
    val client = httpClient()
    val response =
        AppObservability.observeUpstreamRequest("judge", operation) {
          client.get(normalizeUrl(url)) { applyJudgeBrowserHeaders() }
        }
    val body = response.bodyAsText()
    if (isSessionExpired(response, body)) {
      if (retry > 0) {
        judgeSessionActivated = false
        ensureJudgeSession(forceRefresh = true)
        return getHtml(operation, url, retry - 1)
      }
      log.info("Judge auth expired for user {}", username)
      throw JudgeAuthenticationException("希冀登录状态异常，请重新登录后重试")
    }
    if (response.status != HttpStatusCode.OK) {
      throw JudgeException("希冀服务暂时不可用，请稍后重试")
    }
    return body
  }

  private fun isSessionExpired(response: HttpResponse, body: String): Boolean {
    if (response.status == HttpStatusCode.Unauthorized) return true
    val finalUrl = response.call.request.url.toString()
    if (isSsoLoginUrl(finalUrl)) return true
    val trimmed = body.trimStart()
    if (
        trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
            trimmed.startsWith("<html", ignoreCase = true)
    ) {
      return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
    }
    return false
  }

  private fun isSsoLoginUrl(url: String): Boolean {
    if (url.contains("sso.buaa.edu.cn/login", ignoreCase = true)) return true
    return url.startsWith(normalizeUrl(SSO_LOGIN_URL), ignoreCase = true)
  }

  private fun resolveRedirectUrl(baseUrl: String, location: String): String =
      runCatching { URI(baseUrl).resolve(location).toString() }.getOrDefault(location)

  private fun HttpRequestBuilder.applyJudgeBrowserHeaders() {
    headers.remove(HttpHeaders.Accept)
    headers.remove(HttpHeaders.AcceptLanguage)
    headers.remove(HttpHeaders.UserAgent)
    header(HttpHeaders.Accept, JUDGE_ACCEPT_HEADER)
    header(HttpHeaders.AcceptLanguage, "zh-CN,zh;q=0.9")
    header(HttpHeaders.UserAgent, JUDGE_USER_AGENT)
  }

  private fun normalizeUrl(url: String): String = VpnCipher.toVpnUrl(url)

  private suspend fun httpClient(): HttpClient =
      ownedClient ?: sessionManager.requireSession(username).client

  companion object {
    private const val BASE_URL = "https://judge.buaa.edu.cn"
    private const val SSO_LOGIN_URL = "https://sso.buaa.edu.cn/login"
    private const val JUDGE_SERVICE_LOGIN_URL =
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F"
    private const val DEFAULT_RETRY_COUNT = 3
    private const val JUDGE_ACCEPT_HEADER =
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    private const val JUDGE_USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
  }
}

private class ForkedJudgeCookieStorage(private val parent: CookiesStorage) : CookiesStorage {
  private val mutex = Mutex()
  private val cookies = linkedMapOf<String, StoredCookie>()

  override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
    mutex.withLock { putCookie(requestUrl, cookie) }
  }

  override suspend fun get(requestUrl: Url): List<Cookie> {
    val parentCookies = parent.get(requestUrl).filterNot { isJudgeScopedCookie(requestUrl, it) }
    val now = System.currentTimeMillis()
    return mutex.withLock {
      parentCookies.forEach { putCookie(requestUrl, it) }
      val result = mutableListOf<Cookie>()
      val expiredKeys = mutableListOf<String>()
      cookies.forEach { (key, stored) ->
        val cookie = stored.cookie
        val expiresAt = cookie.expires?.timestamp
        val maxAge = cookie.maxAge ?: -1
        if (
            (expiresAt != null && expiresAt <= now) ||
                (maxAge >= 0 && now >= stored.createdAt + maxAge * 1000L)
        ) {
          expiredKeys += key
          return@forEach
        }
        if (!domainMatches(requestUrl.host, cookie.domain ?: requestUrl.host)) return@forEach
        if (!pathMatches(requestUrl.encodedPath, cookie.path ?: "/")) return@forEach
        if (cookie.secure && !requestUrl.protocol.name.equals("https", ignoreCase = true)) {
          return@forEach
        }
        result += cookie.copy(expires = expiresAt?.let { GMTDate(it) })
      }
      expiredKeys.forEach(cookies::remove)
      result
    }
  }

  override fun close() {
    cookies.clear()
  }

  private fun putCookie(requestUrl: Url, cookie: Cookie) {
    val normalized =
        cookie.copy(
            domain = (cookie.domain ?: requestUrl.host).lowercase(),
            path = cookie.path ?: requestUrl.encodedPath.ifBlank { "/" },
        )
    val key = cookieKey(normalized)
    if ((normalized.maxAge ?: -1) == 0) {
      cookies.remove(key)
      return
    }
    cookies[key] = StoredCookie(normalized, System.currentTimeMillis())
  }

  private data class StoredCookie(val cookie: Cookie, val createdAt: Long)

  private fun cookieKey(cookie: Cookie): String =
      "${cookie.domain.orEmpty()}|${cookie.path.orEmpty()}|${cookie.name}"

  private fun isJudgeScopedCookie(requestUrl: Url, cookie: Cookie): Boolean {
    val domain = (cookie.domain ?: requestUrl.host).trimStart('.').lowercase()
    if (domain == "judge.buaa.edu.cn" || domain.endsWith(".judge.buaa.edu.cn")) return true
    if (domain == "d.buaa.edu.cn") {
      return webVpnPathTargetsJudge(cookie.path.orEmpty())
    }
    return false
  }

  private fun webVpnPathTargetsJudge(path: String): Boolean {
    val segments = path.split('/').filter { it.isNotBlank() }
    if (segments.size < 2) return false
    return runCatching { VpnCipher.decrypt(segments[1]) }
        .getOrNull()
        ?.equals("judge.buaa.edu.cn", ignoreCase = true) == true
  }

  private fun domainMatches(host: String, domain: String): Boolean {
    val cleanHost = host.lowercase()
    val cleanDomain = domain.trimStart('.').lowercase()
    return cleanHost == cleanDomain || cleanHost.endsWith(".$cleanDomain")
  }

  private fun pathMatches(requestPath: String, cookiePath: String): Boolean {
    val normalizedRequestPath = requestPath.ifBlank { "/" }
    val normalizedCookiePath = if (cookiePath.endsWith("/")) cookiePath else "$cookiePath/"
    return normalizedRequestPath.startsWith(normalizedCookiePath.removeSuffix("/"))
  }
}

private fun buildJudgeWorkerClient(cookieStorage: CookiesStorage): HttpClient {
  return HttpClient(CIO) {
    engine {
      maxConnectionsCount = 8
      requestTimeout = 30_000
      endpoint {
        maxConnectionsPerRoute = 4
        keepAliveTime = 30_000
        connectTimeout = 10_000
        pipelineMaxSize = 2
      }
      val proxyUrl = System.getenv("HTTPS_PROXY") ?: System.getenv("HTTP_PROXY")
      if (!proxyUrl.isNullOrBlank()) {
        proxy = io.ktor.client.engine.ProxyBuilder.http(io.ktor.http.Url(proxyUrl))
      }
      if (System.getenv("TRUST_ALL_CERTS")?.lowercase() == "true") {
        https {
          trustManager =
              object : javax.net.ssl.X509TrustManager {
                override fun checkClientTrusted(
                    c: Array<java.security.cert.X509Certificate>?,
                    a: String?,
                ) {}

                override fun checkServerTrusted(
                    c: Array<java.security.cert.X509Certificate>?,
                    a: String?,
                ) {}

                override fun getAcceptedIssuers(): Array<java.security.cert.X509Certificate> =
                    arrayOf()
              }
        }
      }
    }
    install(HttpCookies) { storage = cookieStorage }
    install(HttpTimeout) {
      requestTimeoutMillis = 30_000
      connectTimeoutMillis = 10_000
    }
    followRedirects = true
    defaultRequest {
      headers.append(HttpHeaders.UserAgent, "UBAA-Backend/1.0")
      headers.append(HttpHeaders.Accept, "application/json, text/html, */*")
    }
  }
}
