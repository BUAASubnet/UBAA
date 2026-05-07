package cn.edu.ubaa.api.local

import cn.edu.ubaa.api.ConnectionMode
import cn.edu.ubaa.api.ConnectionRuntime
import cn.edu.ubaa.api.ModeScopedSessionStore
import cn.edu.ubaa.api.auth.ApiCallException
import cn.edu.ubaa.api.auth.toUserFacingApiException
import cn.edu.ubaa.api.feature.JudgeApiBackend
import cn.edu.ubaa.api.storage.CredentialStore
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailKeyDto
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailsResponse
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeAssignmentsResponse
import cn.edu.ubaa.model.dto.JudgeProblemDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import com.russhwolf.settings.Settings
import io.ktor.client.HttpClient
import io.ktor.client.plugins.cookies.CookiesStorage
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
import kotlin.time.Clock
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

internal class LocalJudgeApiBackend(
    private val nowProvider: () -> LocalDateTime = {
      Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    }
) : JudgeApiBackend {
  override suspend fun getAssignments(
      includeExpired: Boolean,
      userKey: String?,
  ): Result<JudgeAssignmentsResponse> =
      runLocalJudgeCall("希冀作业列表加载失败，请稍后重试") { session ->
        getAssignmentsResponse(
            includeExpired = includeExpired,
            userKey = resolveJudgeCourseSkipUserKey(userKey, session),
        )
      }

  override suspend fun getAssignmentDetail(
      courseId: String,
      assignmentId: String,
  ): Result<JudgeAssignmentDetailDto> =
      runLocalJudgeCall("希冀作业详情加载失败，请稍后重试") { _ ->
        getAssignmentDetailResponse(courseId, assignmentId)
      }

  override suspend fun getAssignmentDetails(
      keys: List<JudgeAssignmentDetailKeyDto>
  ): Result<JudgeAssignmentDetailsResponse> =
      runLocalJudgeCall("希冀作业详情加载失败，请稍后重试") { _ -> getAssignmentDetailsResponse(keys) }

  private suspend fun LocalJudgeClient.getAssignmentsResponse(
      includeExpired: Boolean,
      userKey: String,
  ): JudgeAssignmentsResponse {
    val courses = getCoursesCached()
    val skippedCourseIds =
        if (includeExpired) emptySet()
        else LocalJudgeHistoricalCourseStore.get(cacheScope.mode, userKey)
    val courseResults =
        courses
            .filter { course -> includeExpired || course.courseId !in skippedCourseIds }
            .mapConcurrently(LOCAL_JUDGE_ASSIGNMENT_QUERY_CONCURRENCY) { course ->
              withIsolatedClient { worker ->
                getAssignmentSummaries(
                    course = course,
                    includeExpired = includeExpired,
                    worker = worker,
                )
              }
            }
    val historicalCutoffCourseIds = courseResults.flatMap { it.historicalCutoffCourseIds }.toSet()
    val assignments =
        courseResults
            .flatMap { it.summaries }
            .sortedWith(
                compareBy<JudgeAssignmentSummaryDto> { it.dueTime ?: "9999-99-99 99:99:99" }
                    .thenBy { it.courseName }
                    .thenBy { it.title }
            )
    LocalJudgeHistoricalCourseStore.add(
        mode = cacheScope.mode,
        userKey = userKey,
        courseIds = historicalCutoffCourseIds,
    )

    return JudgeAssignmentsResponse(
        assignments = assignments,
        historicalCutoffCourseIds = historicalCutoffCourseIds.sorted(),
    )
  }

  private data class LocalJudgeAssignmentSummaryResult(
      val summaries: List<JudgeAssignmentSummaryDto>,
      val historicalCutoffCourseIds: Set<String>,
  )

  private suspend fun LocalJudgeClient.getAssignmentSummaries(
      course: LocalJudgeCourseRaw,
      includeExpired: Boolean,
      worker: LocalJudgeClient,
  ): LocalJudgeAssignmentSummaryResult {
    val assignments = getAssignmentsCached(course) { worker.getAssignments(course) }
    val summaries = mutableListOf<JudgeAssignmentSummaryDto>()
    var reachedHistoricalCutoff = false
    for (assignment in assignments) {
      val cacheKey =
          LocalJudgeDetailCacheKey(
              scope = cacheScope,
              courseId = assignment.courseId,
              assignmentId = assignment.assignmentId,
          )
      val detail =
          getDetailCached(cacheKey) {
            worker.getAssignmentDetail(
                courseId = assignment.courseId,
                courseName = assignment.courseName,
                assignmentId = assignment.assignmentId,
                title = assignment.title,
            )
          }
      if (detail.startedBeforeSixMonthCutoff()) {
        reachedHistoricalCutoff = true
        if (!includeExpired) {
          break
        }
      }
      summaries += detail.toSummary()
    }
    return LocalJudgeAssignmentSummaryResult(
        summaries = summaries,
        historicalCutoffCourseIds =
            if (reachedHistoricalCutoff) setOf(course.courseId) else emptySet(),
    )
  }

  private suspend fun LocalJudgeClient.getAssignmentDetailResponse(
      courseId: String,
      assignmentId: String,
  ): JudgeAssignmentDetailDto =
      getAssignmentDetailsResponse(
              listOf(JudgeAssignmentDetailKeyDto(courseId = courseId, assignmentId = assignmentId))
          )
          .details
          .firstOrNull() ?: throw localJudgeNotFoundException()

  private suspend fun LocalJudgeClient.getAssignmentDetailsResponse(
      keys: List<JudgeAssignmentDetailKeyDto>
  ): JudgeAssignmentDetailsResponse {
    val normalizedKeys = normalizeLocalJudgeDetailKeys(keys)
    if (normalizedKeys.isEmpty()) return JudgeAssignmentDetailsResponse(emptyList())

    val courses = getCoursesCached().associateBy { it.courseId }
    val details =
        normalizedKeys
            .groupBy { it.courseId }
            .entries
            .mapConcurrently(LOCAL_JUDGE_ASSIGNMENT_QUERY_CONCURRENCY) { (courseId, courseKeys) ->
              val course = courses[courseId] ?: throw localJudgeNotFoundException()
              withIsolatedClient { worker ->
                val assignments =
                    getAssignmentsCached(course) { worker.getAssignments(course) }
                        .associateBy { it.assignmentId }
                courseKeys.map { key ->
                  val assignment =
                      assignments[key.assignmentId] ?: throw localJudgeNotFoundException()
                  val cacheKey =
                      LocalJudgeDetailCacheKey(
                          scope = cacheScope,
                          courseId = assignment.courseId,
                          assignmentId = assignment.assignmentId,
                      )
                  getDetailCached(cacheKey) {
                    worker.getAssignmentDetail(
                        courseId = assignment.courseId,
                        courseName = assignment.courseName,
                        assignmentId = assignment.assignmentId,
                        title = assignment.title,
                    )
                  }
                }
              }
            }
            .flatten()

    return JudgeAssignmentDetailsResponse(details)
  }

  private suspend fun <T> runLocalJudgeCall(
      defaultMessage: String,
      block: suspend LocalJudgeClient.(LocalAuthSession) -> T,
  ): Result<T> {
    val session =
        LocalAuthSessionStore.get() ?: return Result.failure(localUnauthenticatedApiException())

    return try {
      val mode =
          ConnectionRuntime.currentMode()?.takeIf { it != ConnectionMode.SERVER_RELAY }
              ?: ConnectionMode.DIRECT
      Result.success(
          LocalJudgeClient(cacheScope = LocalJudgeCacheScope(mode, session.username)).block(session)
      )
    } catch (e: LocalJudgeAuthenticationException) {
      Result.failure(resolveLocalBusinessAuthenticationFailure("judge_auth_failed"))
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException(defaultMessage))
    }
  }

  private fun JudgeAssignmentDetailDto.startedBeforeSixMonthCutoff(): Boolean {
    val startAt = parseLocalJudgeDateTime(startTime) ?: return false
    return startAt < nowProvider().minusLocalJudgeMonths(6)
  }
}

private class LocalJudgeClient(
    private val httpClient: HttpClient = LocalUpstreamClientProvider.shared(),
    private val ownsHttpClient: Boolean = false,
    val cacheScope: LocalJudgeCacheScope,
) {
  private val courseSelectionMutex = Mutex()
  private var judgeSessionActivated = false

  suspend fun getCourses(): List<LocalJudgeCourseRaw> {
    ensureJudgeSession()
    val body = getHtml("get_courses", "$BASE_URL/courselist.jsp?courseID=0")
    return LocalJudgeHtmlParsers.parseCourses(body)
  }

  suspend fun getAssignments(course: LocalJudgeCourseRaw): List<LocalJudgeAssignmentRaw> {
    ensureJudgeSession()
    return courseSelectionMutex.withLock {
      selectCourse(course.courseId)
      val body = getHtml("get_assignments", "$BASE_URL/assignment/index.jsp")
      LocalJudgeHtmlParsers.parseAssignments(body, course)
    }
  }

  suspend fun getAssignmentDetail(
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
  ): JudgeAssignmentDetailDto {
    ensureJudgeSession()
    return courseSelectionMutex.withLock {
      selectCourse(courseId)
      val body =
          getHtml("get_assignment_detail", "$BASE_URL/assignment/index.jsp?assignID=$assignmentId")
      LocalJudgeHtmlParsers.parseAssignmentDetail(
          html = body,
          courseId = courseId,
          courseName = courseName,
          assignmentId = assignmentId,
          title = title,
      )
    }
  }

  suspend fun getCoursesCached(): List<LocalJudgeCourseRaw> {
    LocalJudgeApiCache.getCourses(cacheScope)?.let {
      return it
    }
    val fetched = getCourses()
    if (fetched.isNotEmpty()) {
      LocalJudgeApiCache.putCourses(cacheScope, fetched)
    }
    return fetched
  }

  suspend fun getAssignmentsCached(
      course: LocalJudgeCourseRaw,
      fetch: suspend () -> List<LocalJudgeAssignmentRaw>,
  ): List<LocalJudgeAssignmentRaw> {
    val key = LocalJudgeCourseCacheKey(cacheScope, course.courseId)
    LocalJudgeApiCache.getAssignments(key)?.let {
      return it
    }
    val fetched = fetch()
    if (fetched.isNotEmpty()) {
      LocalJudgeApiCache.putAssignments(key, fetched)
    } else {
      LocalJudgeApiCache.clearAssignments(key)
    }
    return fetched
  }

  suspend fun getDetailCached(
      key: LocalJudgeDetailCacheKey,
      fetch: suspend () -> JudgeAssignmentDetailDto,
  ): JudgeAssignmentDetailDto {
    LocalJudgeApiCache.getDetail(key)?.let {
      return it
    }
    val fetched = fetch()
    LocalJudgeApiCache.putDetail(key, fetched)
    return fetched
  }

  private suspend fun ensureJudgeSession(forceRefresh: Boolean = false) {
    if (!forceRefresh && judgeSessionActivated) return
    val response = httpClient.get(judgeServiceLoginUrl()) { applyJudgeBrowserHeaders() }
    val activatedResponse = followJudgeActivationRedirectIfNeeded(response)
    val body = activatedResponse.bodyAsText()
    if (isLocalJudgeSessionExpired(activatedResponse, body)) {
      throw LocalJudgeAuthenticationException("希冀登录状态异常，请重新登录后重试")
    }
    if (activatedResponse.status != HttpStatusCode.OK) {
      throw ApiCallException("希冀服务暂时不可用，请稍后重试", activatedResponse.status, "judge_error")
    }
    judgeSessionActivated = true
  }

  private suspend fun selectCourse(courseId: String) {
    getHtml("select_course", "$BASE_URL/courselist.jsp?courseID=$courseId")
  }

  private suspend fun getHtml(
      operation: String,
      url: String,
      retry: Int = DEFAULT_RETRY_COUNT,
  ): String {
    val response = httpClient.get(localUpstreamUrl(url)) { applyJudgeBrowserHeaders() }
    val body = response.bodyAsText()
    if (isLocalJudgeSessionExpired(response, body)) {
      if (retry > 0) {
        judgeSessionActivated = false
        ensureJudgeSession(forceRefresh = true)
        return getHtml(operation, url, retry - 1)
      }
      throw LocalJudgeAuthenticationException("希冀登录状态异常，请重新登录后重试")
    }
    if (response.status != HttpStatusCode.OK) {
      throw ApiCallException("希冀服务暂时不可用，请稍后重试", response.status, "judge_error")
    }
    return body
  }

  suspend fun <T> withIsolatedClient(block: suspend (LocalJudgeClient) -> T): T {
    val mode =
        ConnectionRuntime.currentMode()?.takeIf { it != ConnectionMode.SERVER_RELAY }
            ?: ConnectionMode.DIRECT
    val cookieStorage = ForkedLocalJudgeCookieStorage(LocalCookieStore.storage(mode))
    val client = LocalUpstreamClientProvider.newClient(cookieStorage)
    val worker =
        LocalJudgeClient(httpClient = client, ownsHttpClient = true, cacheScope = cacheScope)
    return try {
      block(worker)
    } finally {
      worker.close()
    }
  }

  private suspend fun followJudgeActivationRedirectIfNeeded(response: HttpResponse): HttpResponse {
    if (response.status.value !in 300..399) return response
    val location =
        response.headers[HttpHeaders.Location]?.takeIf { it.isNotBlank() } ?: return response
    val redirectUrl = resolveJudgeRedirectUrl(response.call.request.url.toString(), location)
    return httpClient.get(localUpstreamUrl(redirectUrl)) { applyJudgeBrowserHeaders() }
  }

  private fun close() {
    if (ownsHttpClient) {
      httpClient.close()
    }
  }

  companion object {
    private const val BASE_URL = "https://judge.buaa.edu.cn"
    private const val DEFAULT_RETRY_COUNT = 3
  }
}

private class ForkedLocalJudgeCookieStorage(private val parent: CookiesStorage) : CookiesStorage {
  private val mutex = Mutex()
  private val cookies = linkedMapOf<String, StoredCookie>()

  override suspend fun addCookie(requestUrl: Url, cookie: Cookie) {
    mutex.withLock { putCookie(requestUrl, cookie) }
  }

  override suspend fun get(requestUrl: Url): List<Cookie> {
    val parentCookies = parent.get(requestUrl).filterNot { isJudgeScopedCookie(requestUrl, it) }
    val now = localJudgeNowMillis()
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
    cookies[key] = StoredCookie(normalized, localJudgeNowMillis())
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
    val resolved = LocalWebVpnSupport.fromWebVpnUrl("https://d.buaa.edu.cn$path")
    return resolved.contains("judge.buaa.edu.cn", ignoreCase = true)
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

private fun judgeServiceLoginUrl(): String = localUpstreamUrl(JUDGE_SERVICE_LOGIN_URL)

private const val JUDGE_SERVICE_LOGIN_URL =
    "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F"

private fun HttpRequestBuilder.applyJudgeBrowserHeaders() {
  header(HttpHeaders.Accept, JUDGE_ACCEPT_HEADER)
  header(HttpHeaders.AcceptLanguage, "zh-CN,zh;q=0.9")
  header(HttpHeaders.UserAgent, JUDGE_USER_AGENT)
}

private const val JUDGE_ACCEPT_HEADER =
    "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"

private const val JUDGE_USER_AGENT =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"

private fun resolveJudgeRedirectUrl(baseUrl: String, location: String): String {
  if (location.startsWith("http://") || location.startsWith("https://")) return location
  val currentUrl = runCatching { Url(baseUrl) }.getOrNull() ?: return location
  if (location.startsWith("//")) return "${currentUrl.protocol.name}:$location"
  val authority =
      "${currentUrl.protocol.name}://${currentUrl.host}${if (currentUrl.specifiedPort != currentUrl.protocol.defaultPort) ":${currentUrl.specifiedPort}" else ""}"
  if (location.startsWith("/")) return "$authority$location"
  val basePath = currentUrl.encodedPath.substringBeforeLast('/', "")
  val separator = if (basePath.endsWith("/")) "" else "/"
  return "$authority$basePath$separator$location"
}

private class LocalJudgeAuthenticationException(message: String) : RuntimeException(message)

internal data class LocalJudgeCourseRaw(
    val courseId: String,
    val courseName: String,
)

internal data class LocalJudgeAssignmentRaw(
    val assignmentId: String,
    val courseId: String,
    val courseName: String,
    val title: String,
)

internal data class LocalJudgeCacheScope(
    val mode: ConnectionMode,
    val username: String,
)

internal data class LocalJudgeCourseCacheKey(
    val scope: LocalJudgeCacheScope,
    val courseId: String,
)

internal data class LocalJudgeDetailCacheKey(
    val scope: LocalJudgeCacheScope,
    val courseId: String,
    val assignmentId: String,
)

internal object LocalJudgeApiCache {
  private data class Entry<T>(
      val value: T,
      val cachedAt: Long,
  )

  private val mutex = Mutex()
  private val coursesByScope =
      mutableMapOf<LocalJudgeCacheScope, Entry<List<LocalJudgeCourseRaw>>>()
  private val assignmentsByCourse =
      mutableMapOf<LocalJudgeCourseCacheKey, Entry<List<LocalJudgeAssignmentRaw>>>()
  private val detailsByAssignment =
      mutableMapOf<LocalJudgeDetailCacheKey, Entry<JudgeAssignmentDetailDto>>()

  fun clearAll() {
    coursesByScope.clear()
    assignmentsByCourse.clear()
    detailsByAssignment.clear()
  }

  suspend fun getCourses(scope: LocalJudgeCacheScope): List<LocalJudgeCourseRaw>? =
      mutex.withLock { coursesByScope[scope]?.takeIfFresh(LOCAL_JUDGE_LIST_TTL_MILLIS)?.value }

  suspend fun putCourses(
      scope: LocalJudgeCacheScope,
      courses: List<LocalJudgeCourseRaw>,
  ) {
    mutex.withLock { coursesByScope[scope] = Entry(courses, localJudgeNowMillis()) }
  }

  suspend fun getAssignments(key: LocalJudgeCourseCacheKey): List<LocalJudgeAssignmentRaw>? =
      mutex.withLock { assignmentsByCourse[key]?.takeIfFresh(LOCAL_JUDGE_LIST_TTL_MILLIS)?.value }

  suspend fun putAssignments(
      key: LocalJudgeCourseCacheKey,
      assignments: List<LocalJudgeAssignmentRaw>,
  ) {
    mutex.withLock { assignmentsByCourse[key] = Entry(assignments, localJudgeNowMillis()) }
  }

  suspend fun clearAssignments(key: LocalJudgeCourseCacheKey) {
    mutex.withLock { assignmentsByCourse.remove(key) }
  }

  suspend fun getDetail(key: LocalJudgeDetailCacheKey): JudgeAssignmentDetailDto? =
      mutex.withLock { detailsByAssignment[key]?.takeIfFresh(LOCAL_JUDGE_DETAIL_TTL_MILLIS)?.value }

  suspend fun putDetail(
      key: LocalJudgeDetailCacheKey,
      detail: JudgeAssignmentDetailDto,
  ) {
    mutex.withLock { detailsByAssignment[key] = Entry(detail, localJudgeNowMillis()) }
  }

  private fun <T> Entry<T>.takeIfFresh(ttlMillis: Long): Entry<T>? = takeIf {
    localJudgeNowMillis() - cachedAt < ttlMillis
  }
}

internal object LocalJudgeHistoricalCourseStore {
  private const val KEY_LOCAL_JUDGE_HISTORICAL_COURSES = "local_judge_historical_courses"
  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun get(mode: ConnectionMode, userKey: String): Set<String> =
      settings
          .getStringOrNull(storageKey(mode, userKey))
          ?.lineSequence()
          ?.map { it.trim() }
          ?.filter { it.isNotBlank() }
          ?.toSet() ?: emptySet()

  fun add(
      mode: ConnectionMode,
      userKey: String,
      courseIds: Iterable<String>,
  ) {
    val normalizedCourseIds = courseIds.map { it.trim() }.filter { it.isNotBlank() }
    if (normalizedCourseIds.isEmpty()) return
    val merged = get(mode, userKey) + normalizedCourseIds
    settings.putString(storageKey(mode, userKey), merged.sorted().joinToString("\n"))
  }

  private fun storageKey(mode: ConnectionMode, userKey: String): String =
      ModeScopedSessionStore.scopedKey(
          "${KEY_LOCAL_JUDGE_HISTORICAL_COURSES}_${sanitizeUserKey(userKey)}",
          mode,
      )

  private fun sanitizeUserKey(userKey: String): String =
      userKey.trim().ifBlank { "default" }.replace(Regex("""[^A-Za-z0-9_.-]"""), "_")
}

internal fun resolveJudgeCourseSkipUserKey(
    explicitUserKey: String?,
    localSession: LocalAuthSession? = null,
): String =
    explicitUserKey?.takeIf { it.isNotBlank() }
        ?: localSession?.user?.schoolid?.takeIf { it.isNotBlank() }
        ?: localSession?.username?.takeIf { it.isNotBlank() }
        ?: CredentialStore.getUsername()?.takeIf { it.isNotBlank() }
        ?: "default"

private fun normalizeLocalJudgeDetailKeys(
    keys: List<JudgeAssignmentDetailKeyDto>
): List<JudgeAssignmentDetailKeyDto> =
    keys
        .filter { it.courseId.isNotBlank() && it.assignmentId.isNotBlank() }
        .distinctBy { it.courseId to it.assignmentId }

private object LocalJudgeHtmlParsers {
  private val linkOptions = setOf(RegexOption.IGNORE_CASE)
  private val tagRegex = Regex("""<[^>]+>""")
  private val rowRegex = Regex("""<tr\b[^>]*>([\s\S]*?)</tr>""", linkOptions)
  private val cellRegex = Regex("""<(?:th|td)\b[^>]*>([\s\S]*?)</(?:th|td)>""", linkOptions)
  private val tableTagRegex = Regex("""</?table\b[^>]*>""", RegexOption.IGNORE_CASE)
  private val unsubmittedMarkers = listOf("还未提交代码", "未提交文件", "未提交答案", "未作答", "未提交")
  private val submittedMarkers =
      listOf(
          "初次提交时间",
          "首次提交时间",
          "最近一次提交时间",
          "最后一次提交时间",
          "最后一次修改时间",
          "已提交",
          "得分",
          "Accepted",
          "Accept",
      )

  fun parseCourses(html: String): List<LocalJudgeCourseRaw> {
    val regex =
        Regex(
            """<a\b[^>]*href\s*=\s*(?:"[^"]*courselist\.jsp\?courseID=(\d+)[^"]*"|'[^']*courselist\.jsp\?courseID=(\d+)[^']*'|[^\s>]*courselist\.jsp\?courseID=(\d+)[^\s>]*)[^>]*>([\s\S]*?)</a>""",
            linkOptions,
        )
    return regex
        .findAll(html)
        .mapNotNull { match ->
          val courseId =
              match.groupValues.drop(1).take(3).firstOrNull { it.isNotBlank() }
                  ?: return@mapNotNull null
          if (courseId == "0") return@mapNotNull null
          val courseName = cleanText(stripTags(match.groupValues[4]))
          courseName.takeIf { it.isNotBlank() }?.let { LocalJudgeCourseRaw(courseId, it) }
        }
        .distinctBy { it.courseId }
        .toList()
  }

  fun parseAssignments(
      html: String,
      course: LocalJudgeCourseRaw,
  ): List<LocalJudgeAssignmentRaw> {
    val regex =
        Regex(
            """<a\b[^>]*href\s*=\s*(?:"([^"]*assignID=(\d+)[^"]*)"|'([^']*assignID=(\d+)[^']*)'|([^\s>]*assignID=(\d+)[^\s>]*))[^>]*>([\s\S]*?)</a>""",
            linkOptions,
        )
    return regex
        .findAll(html)
        .mapNotNull { match ->
          val href =
              listOf(match.groupValues[1], match.groupValues[3], match.groupValues[5]).firstOrNull {
                it.isNotBlank()
              } ?: return@mapNotNull null
          val assignmentId =
              listOf(match.groupValues[2], match.groupValues[4], match.groupValues[6]).firstOrNull {
                it.isNotBlank()
              } ?: return@mapNotNull null
          if (href.contains("problemContent") || href.contains("judgeDetails")) {
            return@mapNotNull null
          }
          val title = cleanText(stripTags(match.groupValues[7]))
          title
              .takeIf { it.isNotBlank() }
              ?.let {
                LocalJudgeAssignmentRaw(
                    assignmentId = assignmentId,
                    courseId = course.courseId,
                    courseName = course.courseName,
                    title = it,
                )
              }
        }
        .distinctBy { it.assignmentId }
        .toList()
  }

  fun parseAssignmentDetail(
      html: String,
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
  ): JudgeAssignmentDetailDto {
    val plainText = htmlToText(html)
    val startAndEnd =
        Regex(
                """作业时间[：:]\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)\s*至\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?)"""
            )
            .find(plainText)
    val maxScore = Regex("""作业满分[：:]\s*([\d.]+)""").find(plainText)?.groupValues?.get(1)
    val totalProblems =
        Regex("""共\s*(\d+)\s*道""").find(plainText)?.groupValues?.get(1)?.toIntOrNull() ?: 0
    val explicitMyScore = Regex("""总分[：:]\s*([\d.]+)""").find(plainText)?.groupValues?.get(1)
    val parsedProblems = parseProblems(html)
    val earnedScores = parsedProblems.mapNotNull { it.earnedScore }
    val problems = parsedProblems.map { it.problem }
    val fallbackSubmitted = if (problems.isEmpty()) estimateSubmittedCount(plainText) else 0
    val submittedCount =
        if (problems.isNotEmpty()) {
          problems.count { it.status != JudgeSubmissionStatus.UNSUBMITTED }
        } else {
          fallbackSubmitted
        }
    val resolvedTotalProblems =
        if (totalProblems == 0 && problems.isNotEmpty()) problems.size else totalProblems
    val myScore =
        explicitMyScore ?: earnedScores.takeIf { it.isNotEmpty() }?.sum()?.let(::formatScore)
    val status = resolveStatus(resolvedTotalProblems, submittedCount)

    return JudgeAssignmentDetailDto(
        courseId = courseId,
        courseName = courseName,
        assignmentId = assignmentId,
        title = title,
        startTime = startAndEnd?.groupValues?.get(1)?.let(::normalizeDateTime),
        dueTime = startAndEnd?.groupValues?.get(2)?.let(::normalizeDateTime),
        maxScore = maxScore?.toDoubleOrNull()?.let(::formatScore) ?: maxScore,
        myScore = myScore?.toDoubleOrNull()?.let(::formatScore) ?: myScore,
        totalProblems = resolvedTotalProblems,
        submittedCount = submittedCount,
        submissionStatus = status,
        submissionStatusText =
            submissionStatusText(status, submittedCount, resolvedTotalProblems, myScore, maxScore),
        problems = problems,
        contentPlainText = plainText.ifBlank { null },
    )
  }

  private data class ParsedProblem(
      val problem: JudgeProblemDto,
      val earnedScore: Double?,
  )

  private fun parseProblems(html: String): List<ParsedProblem> {
    return extractTopLevelTables(html).flatMap { table ->
      rowRegex.findAll(removeNestedTables(table)).mapNotNull { row ->
        val cells =
            cellRegex
                .findAll(row.groupValues[1])
                .map { cell -> cleanText(stripTags(cell.groupValues[1])) }
                .toList()
        parseProblemFromCells(cells)
      }
    }
  }

  private fun parseProblemFromCells(cells: List<String>): ParsedProblem? {
    if (cells.size >= 4) {
      val maxScore = parseNumber(cells[2]) ?: return null
      val statusText = cells.drop(3).joinToString(" ")
      val status = detectProblemStatus(statusText) ?: return null
      val earnedScore = parseEarnedScore(statusText)
      return ParsedProblem(
          problem =
              JudgeProblemDto(
                  name = cells[1],
                  score =
                      (earnedScore
                              ?: if (status == JudgeSubmissionStatus.SUBMITTED) maxScore else null)
                          ?.let(::formatScore),
                  maxScore = formatScore(maxScore),
                  status = status,
                  statusText = problemStatusText(status),
              ),
          earnedScore = earnedScore,
      )
    }

    if (cells.size == 2) {
      val status = detectProblemStatus(cells[1]) ?: return null
      val earnedScore = parseEarnedScore(cells[1])
      val index = cells[0].trim().trimEnd('.')
      return ParsedProblem(
          problem =
              JudgeProblemDto(
                  name = if (index.isBlank()) "题目" else "第${index}题",
                  score = earnedScore?.let(::formatScore),
                  maxScore = earnedScore?.let(::formatScore),
                  status = status,
                  statusText = problemStatusText(status),
              ),
          earnedScore = earnedScore,
      )
    }

    return null
  }

  private fun extractTopLevelTables(html: String): List<String> {
    val tables = mutableListOf<String>()
    var depth = 0
    var startIndex = -1
    for (match in tableTagRegex.findAll(html)) {
      val isOpening = !match.value.startsWith("</")
      if (isOpening) {
        if (depth == 0) startIndex = match.range.first
        depth++
      } else if (depth > 0) {
        depth--
        if (depth == 0 && startIndex >= 0) {
          tables += html.substring(startIndex, match.range.last + 1)
          startIndex = -1
        }
      }
    }
    return tables
  }

  private fun removeNestedTables(tableHtml: String): String {
    val output = StringBuilder()
    var depth = 0
    var lastIndex = 0
    for (match in tableTagRegex.findAll(tableHtml)) {
      val isOpening = !match.value.startsWith("</")
      if (isOpening) {
        if (depth <= 1) output.append(tableHtml.substring(lastIndex, match.range.first))
        depth++
        if (depth <= 1) output.append(match.value)
      } else {
        if (depth <= 1) output.append(tableHtml.substring(lastIndex, match.range.first))
        if (depth <= 1) output.append(match.value)
        if (depth > 0) depth--
      }
      lastIndex = match.range.last + 1
    }
    if (depth <= 1 && lastIndex < tableHtml.length) output.append(tableHtml.substring(lastIndex))
    return output.toString()
  }

  private fun estimateSubmittedCount(text: String): Int {
    val choiceEnd =
        listOf("填空题", "编程题", "文件上传题").map { text.indexOf(it) }.filter { it >= 0 }.minOrNull()
            ?: text.length
    val choiceCount = Regex("""得分[：:]\s*[\d.]+""").findAll(text.substring(0, choiceEnd)).count()
    val fillStart = text.indexOf("填空题")
    val fillCount =
        if (fillStart >= 0) {
          val nextSection =
              listOf("编程题", "文件上传题")
                  .map { text.indexOf(it, fillStart + 2) }
                  .filter { it >= 0 }
                  .minOrNull() ?: text.length
          Regex("""得分[：:]\s*[\d.]+""").findAll(text.substring(fillStart, nextSection)).count()
        } else {
          0
        }
    val programmingCount =
        text
            .indexOf("编程题")
            .takeIf { it >= 0 }
            ?.let { Regex("""最后一次提交时间""").findAll(text.substring(it)).count() } ?: 0
    val fileCount =
        text
            .indexOf("文件上传题")
            .takeIf { it >= 0 }
            ?.let { Regex("""初次提交时间""").findAll(text.substring(it)).count() } ?: 0
    return choiceCount + fillCount + programmingCount + fileCount
  }

  private fun detectProblemStatus(text: String): JudgeSubmissionStatus? {
    val normalized = cleanText(text)
    if (unsubmittedMarkers.any { normalized.contains(it) }) return JudgeSubmissionStatus.UNSUBMITTED
    if (submittedMarkers.any { normalized.contains(it, ignoreCase = true) }) {
      return JudgeSubmissionStatus.SUBMITTED
    }
    return null
  }

  private fun resolveStatus(totalProblems: Int, submittedCount: Int): JudgeSubmissionStatus =
      when {
        totalProblems <= 0 -> JudgeSubmissionStatus.UNKNOWN
        submittedCount <= 0 -> JudgeSubmissionStatus.UNSUBMITTED
        submittedCount < totalProblems -> JudgeSubmissionStatus.PARTIAL
        else -> JudgeSubmissionStatus.SUBMITTED
      }

  private fun submissionStatusText(
      status: JudgeSubmissionStatus,
      submittedCount: Int,
      totalProblems: Int,
      myScore: String?,
      maxScore: String?,
  ): String =
      when (status) {
        JudgeSubmissionStatus.SUBMITTED ->
            if (!myScore.isNullOrBlank() && !maxScore.isNullOrBlank()) {
              "已完成 $myScore/$maxScore"
            } else {
              "已完成"
            }
        JudgeSubmissionStatus.PARTIAL -> "进行中($submittedCount/$totalProblems)"
        JudgeSubmissionStatus.UNSUBMITTED -> "未提交"
        JudgeSubmissionStatus.UNKNOWN -> "未知状态"
      }

  private fun problemStatusText(status: JudgeSubmissionStatus): String =
      when (status) {
        JudgeSubmissionStatus.SUBMITTED -> "已提交"
        JudgeSubmissionStatus.UNSUBMITTED -> "未提交"
        JudgeSubmissionStatus.PARTIAL -> "部分提交"
        JudgeSubmissionStatus.UNKNOWN -> "未知状态"
      }

  private fun parseNumber(value: String): Double? {
    val text = cleanText(value)
    return if (Regex("""\d+(?:\.\d+)?""").matches(text)) text.toDoubleOrNull() else null
  }

  private fun parseEarnedScore(value: String): Double? =
      Regex("""得分[：:]\s*([\d.]+)""").find(cleanText(value))?.groupValues?.get(1)?.toDoubleOrNull()

  private fun normalizeDateTime(value: String): String =
      if (value.count { it == ':' } == 1) "$value:00" else value

  private fun formatScore(value: Double): String {
    val integer = value.toLong()
    return if (value == integer.toDouble()) integer.toString() else value.toString()
  }

  private fun htmlToText(html: String): String =
      cleanText(stripTags(html.replace(Regex("""<script\b[\s\S]*?</script>""", linkOptions), " ")))

  private fun stripTags(value: String): String = tagRegex.replace(value, " ")

  private fun cleanText(value: String): String =
      decodeEntities(value).replace('\u00a0', ' ').replace(Regex("""\s+"""), " ").trim()

  private fun decodeEntities(value: String): String =
      value
          .replace("&nbsp;", " ")
          .replace("&amp;", "&")
          .replace("&lt;", "<")
          .replace("&gt;", ">")
          .replace("&quot;", "\"")
          .replace("&#39;", "'")
}

private fun JudgeAssignmentDetailDto.toSummary(): JudgeAssignmentSummaryDto =
    JudgeAssignmentSummaryDto(
        courseId = courseId,
        courseName = courseName,
        assignmentId = assignmentId,
        title = title,
        startTime = startTime,
        dueTime = dueTime,
        maxScore = maxScore,
        myScore = myScore,
        totalProblems = totalProblems,
        submittedCount = submittedCount,
        submissionStatus = submissionStatus,
        submissionStatusText = submissionStatusText,
    )

private fun LocalJudgeAssignmentRaw.toSummary(): JudgeAssignmentSummaryDto =
    JudgeAssignmentSummaryDto(
        courseId = courseId,
        courseName = courseName,
        assignmentId = assignmentId,
        title = title,
        submissionStatus = JudgeSubmissionStatus.UNKNOWN,
        submissionStatusText = "未知状态",
    )

private fun localJudgeNotFoundException(): ApiCallException =
    ApiCallException(
        message = "希冀作业不存在或无权限访问，请刷新后重试",
        status = HttpStatusCode.NotFound,
        code = "judge_not_found",
    )

private suspend fun <T, R> Iterable<T>.mapConcurrently(
    concurrency: Int,
    transform: suspend (T) -> R,
): List<R> = coroutineScope {
  val semaphore = Semaphore(concurrency)
  map { item -> async { semaphore.withPermit { transform(item) } } }.awaitAll()
}

private fun localJudgeNowMillis(): Long = Clock.System.now().toEpochMilliseconds()

private fun parseLocalJudgeDateTime(value: String?): LocalDateTime? {
  val normalized = value?.trim()?.takeIf { it.isNotEmpty() }?.replace(" ", "T") ?: return null
  return runCatching { LocalDateTime.parse(normalized) }.getOrNull()
}

private fun LocalDateTime.minusLocalJudgeMonths(months: Int): LocalDateTime {
  var targetYear = year
  var targetMonth = month.ordinal + 1 - months
  while (targetMonth <= 0) {
    targetMonth += 12
    targetYear--
  }
  val targetDay = minOf(day, localJudgeDaysInMonth(targetYear, targetMonth))
  return LocalDateTime(
      targetYear,
      targetMonth,
      targetDay,
      hour,
      minute,
      second,
      nanosecond,
  )
}

private fun localJudgeDaysInMonth(year: Int, month: Int): Int =
    when (month) {
      1,
      3,
      5,
      7,
      8,
      10,
      12 -> 31
      4,
      6,
      9,
      11 -> 30
      2 -> if (localJudgeIsLeapYear(year)) 29 else 28
      else -> 30
    }

private fun localJudgeIsLeapYear(year: Int): Boolean =
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

private const val LOCAL_JUDGE_ASSIGNMENT_QUERY_CONCURRENCY = 4
private const val LOCAL_JUDGE_LIST_TTL_MILLIS = 5 * 60 * 1000L
private const val LOCAL_JUDGE_DETAIL_TTL_MILLIS = 2 * 60 * 1000L

private fun isLocalJudgeSessionExpired(response: HttpResponse, body: String): Boolean {
  if (response.status == HttpStatusCode.Unauthorized) return true
  if (localIsSsoUrl(response.call.request.url.toString())) return true
  val trimmed = body.trimStart()
  if (
      trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
          trimmed.startsWith("<html", ignoreCase = true)
  ) {
    return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
  }
  return false
}
