package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.SpocAssignmentDetailDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocAssignmentsResponse
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.http.contentType
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

internal class LocalSpocApiBackend : SpocApiBackend {
  override suspend fun getAssignments(): Result<SpocAssignmentsResponse> =
      runLocalSpocCall("SPOC 作业列表加载失败，请稍后重试") { getAssignmentsResponse() }

  override suspend fun getAssignmentDetail(
      assignmentId: String
  ): Result<SpocAssignmentDetailDto> =
      runLocalSpocCall("SPOC 作业详情加载失败，请稍后重试") { getAssignmentDetailResponse(assignmentId) }

  private suspend fun LocalSpocClient.getAssignmentsResponse(): SpocAssignmentsResponse {
    val term = getCurrentTerm()
    val termCode = term.mrxq ?: throw ApiCallException("无法获取 SPOC 当前学期代码", code = "spoc_error")
    val courseMap =
        runCatching { getCourses(termCode).associateBy { it.kcid } }.getOrElse { emptyMap() }
    val rawAssignments = getAllAssignments(termCode)
    val assignments =
        rawAssignments
            .map { assignment ->
              val course = assignment.sskcid?.let { courseMap[it] }
              val status =
                  LocalSpocParsers.mapSubmissionStatus(
                      rawStatus = assignment.tjzt,
                      hasContent = !assignment.tjzt.isNullOrBlank(),
                  )
              SpocAssignmentSummaryDto(
                  assignmentId = assignment.zyid,
                  courseId = assignment.sskcid.orEmpty(),
                  courseName = assignment.kcmc ?: course?.kcmc.orEmpty(),
                  teacherName = course?.skjs,
                  title = assignment.zymc,
                  startTime = LocalSpocParsers.normalizeDateTime(assignment.zykssj),
                  dueTime = LocalSpocParsers.normalizeDateTime(assignment.zyjzsj),
                  score = LocalSpocParsers.normalizeScore(assignment.mf),
                  submissionStatus = status,
                  submissionStatusText =
                      LocalSpocParsers.submissionStatusText(status, assignment.tjzt),
              )
            }
            .sortedWith(
                compareBy<SpocAssignmentSummaryDto> { it.dueTime ?: "9999-99-99 99:99:99" }
                    .thenBy { it.courseName }
                    .thenBy { it.title }
            )

    return SpocAssignmentsResponse(
        termCode = termCode,
        termName = term.dqxq,
        assignments = assignments,
    )
  }

  private suspend fun LocalSpocClient.getAssignmentDetailResponse(
      assignmentId: String
  ): SpocAssignmentDetailDto {
    val summary =
        getAssignmentsResponse().assignments.firstOrNull { it.assignmentId == assignmentId }
            ?: throw ApiCallException(
                "未找到指定的 SPOC 作业",
                status = HttpStatusCode.NotFound,
                code = "spoc_error",
            )
    val detail = getAssignmentDetail(assignmentId)
    val submission = runCatching { getSubmission(assignmentId) }.getOrNull()
    val hasSubmission = submission != null
    val status = LocalSpocParsers.mapSubmissionStatus(submission?.tjzt, hasSubmission)

    return summary
        .copy(
            score = LocalSpocParsers.normalizeScore(detail.zyfs) ?: summary.score,
            startTime = LocalSpocParsers.normalizeDateTime(detail.zykssj) ?: summary.startTime,
            dueTime = LocalSpocParsers.normalizeDateTime(detail.zyjzsj) ?: summary.dueTime,
            submissionStatus = status,
            submissionStatusText =
                LocalSpocParsers.submissionStatusText(status, submission?.tjzt),
        )
        .toLocalSpocDetail(
            contentPlainText = LocalSpocParsers.toPlainText(detail.zynr),
            contentHtml = detail.zynr,
            submittedAt = LocalSpocParsers.normalizeDateTime(submission?.tjsj),
        )
  }

  private suspend fun <T> runLocalSpocCall(
      defaultMessage: String,
      block: suspend LocalSpocClient.() -> T,
  ): Result<T> {
    if (LocalAuthSessionStore.get() == null) {
      return Result.failure(localUnauthenticatedApiException())
    }

    return try {
      val client = LocalSpocClient()
      Result.success(client.block())
    } catch (e: LocalSpocAuthenticationException) {
      clearLocalConnectionSession()
      Result.failure(localUnauthenticatedApiException())
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException(defaultMessage))
    }
  }
}

private class LocalSpocClient {
  private val json = Json { ignoreUnknownKeys = true }
  private val requestJson = Json { encodeDefaults = true }

  private var token: String? = null
  private var roleCode: String? = null

  suspend fun getCurrentTerm(): LocalSpocCurrentTermContent {
    return withAuthenticatedCall {
      postEnvelope(
          operation = "get_current_term",
          url = localUpstreamUrl("https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryOne"),
          body = LocalSpocQueryOneRequest(CURRENT_TERM_PARAM),
      )
    }
  }

  suspend fun getCourses(termCode: String): List<LocalSpocCourseRaw> {
    return withAuthenticatedCall {
      getEnvelope<List<LocalSpocCourseRaw>>(
          operation = "get_courses",
          url = localUpstreamUrl("https://spoc.buaa.edu.cn/spocnewht/jxkj/queryKclb"),
      ) {
        parameter("kcmc", "")
        parameter("xnxq", termCode)
      }
    }
  }

  suspend fun getAssignmentsPage(
      termCode: String,
      pageNum: Int,
      pageSize: Int = DEFAULT_PAGE_SIZE,
  ): LocalSpocAssignmentsPageContent {
    return withAuthenticatedCall {
      val plainText =
          requestJson.encodeToString(
              LocalSpocAssignmentsPageRequest(
                  pageSize = pageSize,
                  pageNum = pageNum,
                  sqlid = ASSIGNMENTS_PAGE_SQL_ID,
                  xnxq = termCode,
              )
          )
      postEnvelope(
          operation = "get_assignments_page",
          url = localUpstreamUrl("https://spoc.buaa.edu.cn/spocnewht/inco/ht/queryListByPage"),
          body = LocalSpocEncryptedParamRequest(LocalSpocCrypto.encryptParam(plainText)),
      )
    }
  }

  suspend fun getAllAssignments(termCode: String): List<LocalSpocPagedAssignmentRaw> {
    val assignments = mutableListOf<LocalSpocPagedAssignmentRaw>()
    var pageNum = 1
    while (true) {
      val page = getAssignmentsPage(termCode = termCode, pageNum = pageNum)
      assignments += page.list
      if (!page.hasNextPage || pageNum >= page.pages || page.list.isEmpty()) {
        break
      }
      pageNum++
    }
    return assignments
  }

  suspend fun getAssignmentDetail(assignmentId: String): LocalSpocAssignmentDetailRaw {
    return withAuthenticatedCall {
      getEnvelope(
          operation = "get_assignment_detail",
          url = localUpstreamUrl("https://spoc.buaa.edu.cn/spocnewht/kczy/queryKczyInfoByid"),
      ) {
        parameter("id", assignmentId)
      }
    }
  }

  suspend fun getSubmission(assignmentId: String): LocalSpocSubmissionRaw? {
    return withAuthenticatedCall {
      getEnvelope(
          operation = "get_submission",
          url = localUpstreamUrl("https://spoc.buaa.edu.cn/spocnewht/kczy/queryXsSubmitKczyInfo"),
      ) {
        parameter("kczyid", assignmentId)
      }
    }
  }

  private suspend fun ensureLogin(forceRefresh: Boolean = false) {
    if (!forceRefresh && !token.isNullOrBlank() && !roleCode.isNullOrBlank()) return

    val tokens = fetchLoginTokens()
    val casLogin = performCasLogin(tokens.token)
    val resolvedRoleCode =
        LocalSpocParsers.resolveRoleCode(casLogin)
            ?: throw LocalSpocAuthenticationException("SPOC 登录成功但未获取到角色信息")

    token = tokens.token
    roleCode = resolvedRoleCode
  }

  private suspend fun fetchLoginTokens(): LocalSpocLoginTokens {
    val noRedirectClient = LocalUpstreamClientProvider.newNoRedirectClient()
    return try {
      var currentUrl = localUpstreamUrl("https://spoc.buaa.edu.cn/spocnewht/cas")
      repeat(8) {
        val response = noRedirectClient.get(currentUrl)
        LocalSpocParsers.extractLoginTokens(response.call.request.url.toString())?.let { return it }
        val body = response.bodyAsText()
        if (isLocalSpocSessionExpired(response, body)) {
          throw LocalSpocAuthenticationException("SPOC 登录状态异常，请重新登录后重试")
        }
        val location =
            response.headers[HttpHeaders.Location]
                ?: throw LocalSpocAuthenticationException("SPOC 登录跳转缺少 Location")
        LocalSpocParsers.extractLoginTokens(location)?.let { return it }
        currentUrl = resolveRedirectUrl(response.call.request.url, location)
      }
      throw LocalSpocAuthenticationException("未能在 SPOC 登录跳转链中获取 token")
    } finally {
      noRedirectClient.close()
    }
  }

  private suspend fun performCasLogin(loginToken: String): LocalSpocCasLoginContent {
    return LocalUpstreamClientProvider.shared().post(
        localUpstreamUrl("https://spoc.buaa.edu.cn/spocnewht/sys/casLogin")
    ) {
      contentType(ContentType.Application.Json)
      header("X-Requested-With", "XMLHttpRequest")
      header("Token", "Inco-$loginToken")
      setBody(LocalSpocCasLoginRequest(loginToken))
    }.let { response ->
      val bodyText = response.bodyAsText()
      if (isLocalSpocSessionExpired(response, bodyText)) {
        throw LocalSpocAuthenticationException("SPOC 登录状态异常，请重新登录后重试")
      }
      val envelope = decodeEnvelope<LocalSpocCasLoginContent>(bodyText)
      unwrapEnvelope(envelope, bodyText)
    }
  }

  private suspend inline fun <T> withAuthenticatedCall(crossinline block: suspend () -> T): T {
    ensureLogin()
    return try {
      block()
    } catch (e: LocalSpocAuthenticationException) {
      ensureLogin(forceRefresh = true)
      block()
    }
  }

  private suspend inline fun <reified T> getEnvelope(
      operation: String,
      url: String,
      crossinline builder: io.ktor.client.request.HttpRequestBuilder.() -> Unit = {},
  ): T {
    val currentToken =
        token ?: throw LocalSpocAuthenticationException("SPOC token 未初始化")
    val currentRoleCode =
        roleCode ?: throw LocalSpocAuthenticationException("SPOC roleCode 未初始化")
    val response =
        LocalUpstreamClientProvider.shared().get(url) {
          header("X-Requested-With", "XMLHttpRequest")
          header("Token", "Inco-$currentToken")
          header("RoleCode", currentRoleCode)
          builder()
        }
    val bodyText = response.bodyAsText()
    if (isLocalSpocSessionExpired(response, bodyText)) {
      throw LocalSpocAuthenticationException("SPOC 登录状态已失效")
    }
    val envelope = decodeEnvelope<T>(bodyText)
    return unwrapEnvelope(envelope, bodyText)
  }

  private suspend inline fun <reified T, reified B : Any> postEnvelope(
      operation: String,
      url: String,
      body: B,
  ): T {
    val currentToken =
        token ?: throw LocalSpocAuthenticationException("SPOC token 未初始化")
    val currentRoleCode =
        roleCode ?: throw LocalSpocAuthenticationException("SPOC roleCode 未初始化")
    val response =
        LocalUpstreamClientProvider.shared().post(url) {
          contentType(ContentType.Application.Json)
          header("X-Requested-With", "XMLHttpRequest")
          header("Token", "Inco-$currentToken")
          header("RoleCode", currentRoleCode)
          setBody(body)
        }
    val bodyText = response.bodyAsText()
    if (isLocalSpocSessionExpired(response, bodyText)) {
      throw LocalSpocAuthenticationException("SPOC 登录状态已失效")
    }
    val envelope = decodeEnvelope<T>(bodyText)
    return unwrapEnvelope(envelope, bodyText)
  }

  private inline fun <reified T> decodeEnvelope(bodyText: String): LocalSpocEnvelope<T> {
    return try {
      json.decodeFromString<LocalSpocEnvelope<T>>(bodyText)
    } catch (e: Exception) {
      if (looksLikeAuthenticationFailure("decode_failure", bodyText)) {
        throw LocalSpocAuthenticationException("SPOC 登录状态已失效")
      }
      throw LocalSpocException("SPOC 响应解析失败", e)
    }
  }

  private fun <T> unwrapEnvelope(envelope: LocalSpocEnvelope<T>, bodyText: String): T {
    if (envelope.code == 200 && envelope.content != null) return envelope.content
    if (envelope.code == 200 && bodyText.contains("\"content\":null")) {
      @Suppress("UNCHECKED_CAST")
      return null as T
    }

    val message = envelope.msg ?: envelope.msgEn ?: "SPOC 请求失败"
    if (looksLikeAuthenticationFailure(message, bodyText)) {
      throw LocalSpocAuthenticationException(message)
    }
    throw ApiCallException(message = message, status = HttpStatusCode.BadGateway, code = "spoc_error")
  }

  private fun looksLikeAuthenticationFailure(message: String, bodyText: String): Boolean {
    val text = "$message $bodyText"
    return listOf("登录", "token", "未认证", "未登录", "权限").any {
      text.contains(it, ignoreCase = true)
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
    return "$authority$basePath$separator$location"
  }

  companion object {
    private const val CURRENT_TERM_PARAM =
        "YHrxtTavu6raCwC0/qdgYffB9evWHBkTng/XS4W6j3f/TPo02iEPSoegscDTRNzIPRG49o3RHl4JiFCXAiBkkA=="
    private const val ASSIGNMENTS_PAGE_SQL_ID =
        "1713252980496efac7d5d9985e81693116d3e8a52ebf2b"
    private const val DEFAULT_PAGE_SIZE = 15
  }
}

private fun isLocalSpocSessionExpired(response: HttpResponse, body: String): Boolean {
  if (response.status == HttpStatusCode.Unauthorized) return true
  val finalUrl = response.call.request.url.toString()
  if (localIsSsoUrl(finalUrl)) return true
  val trimmed = body.trimStart()
  if (
      trimmed.startsWith("<!DOCTYPE html", ignoreCase = true) ||
          trimmed.startsWith("<html", ignoreCase = true)
  ) {
    return body.contains("input name=\"execution\"") ||
        body.contains("统一身份认证", ignoreCase = true)
  }
  return false
}
