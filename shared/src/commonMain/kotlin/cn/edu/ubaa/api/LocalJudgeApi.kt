package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeAssignmentsResponse
import cn.edu.ubaa.model.dto.JudgeProblemDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import io.ktor.client.request.HttpRequestBuilder
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode

internal class LocalJudgeApiBackend : JudgeApiBackend {
  override suspend fun getAssignments(): Result<JudgeAssignmentsResponse> =
      runLocalJudgeCall("希冀作业列表加载失败，请稍后重试") { getAssignmentsResponse() }

  override suspend fun getAssignmentDetail(
      courseId: String,
      assignmentId: String,
  ): Result<JudgeAssignmentDetailDto> =
      runLocalJudgeCall("希冀作业详情加载失败，请稍后重试") {
        getAssignmentDetailResponse(courseId, assignmentId)
      }

  private suspend fun LocalJudgeClient.getAssignmentsResponse(): JudgeAssignmentsResponse {
    val assignments =
        getCourses()
            .flatMap { course ->
              getAssignments(course).map { assignment ->
                getAssignmentDetail(
                    courseId = assignment.courseId,
                    courseName = assignment.courseName,
                    assignmentId = assignment.assignmentId,
                    title = assignment.title,
                )
                    .toSummary()
              }
            }
            .sortedWith(
                compareBy<JudgeAssignmentSummaryDto> { it.dueTime ?: "9999-99-99 99:99:99" }
                    .thenBy { it.courseName }
                    .thenBy { it.title }
            )

    return JudgeAssignmentsResponse(assignments)
  }

  private suspend fun LocalJudgeClient.getAssignmentDetailResponse(
      courseId: String,
      assignmentId: String,
  ): JudgeAssignmentDetailDto {
    val course = getCourses().firstOrNull { it.courseId == courseId }
    val courseName = course?.courseName.orEmpty()
    val assignment =
        course?.let { getAssignments(it).firstOrNull { assignment -> assignment.assignmentId == assignmentId } }

    return getAssignmentDetail(
        courseId = courseId,
        courseName = assignment?.courseName ?: courseName,
        assignmentId = assignmentId,
        title = assignment?.title ?: assignmentId,
    )
  }

  private suspend fun <T> runLocalJudgeCall(
      defaultMessage: String,
      block: suspend LocalJudgeClient.() -> T,
  ): Result<T> {
    if (LocalAuthSessionStore.get() == null) {
      return Result.failure(localUnauthenticatedApiException())
    }

    return try {
      Result.success(LocalJudgeClient().block())
    } catch (e: LocalJudgeAuthenticationException) {
      Result.failure(resolveLocalBusinessAuthenticationFailure("judge_auth_failed"))
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException(defaultMessage))
    }
  }
}

private class LocalJudgeClient {
  private var judgeSessionActivated = false

  suspend fun getCourses(): List<LocalJudgeCourseRaw> {
    ensureJudgeSession()
    val body = getHtml("get_courses", "$BASE_URL/courselist.jsp?courseID=0")
    return LocalJudgeHtmlParsers.parseCourses(body)
  }

  suspend fun getAssignments(course: LocalJudgeCourseRaw): List<LocalJudgeAssignmentRaw> {
    ensureJudgeSession()
    selectCourse(course.courseId)
    val body = getHtml("get_assignments", "$BASE_URL/assignment/index.jsp")
    return LocalJudgeHtmlParsers.parseAssignments(body, course)
  }

  suspend fun getAssignmentDetail(
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
  ): JudgeAssignmentDetailDto {
    ensureJudgeSession()
    selectCourse(courseId)
    val body = getHtml("get_assignment_detail", "$BASE_URL/assignment/index.jsp?assignID=$assignmentId")
    return LocalJudgeHtmlParsers.parseAssignmentDetail(
        html = body,
        courseId = courseId,
        courseName = courseName,
        assignmentId = assignmentId,
        title = title,
    )
  }

  private suspend fun ensureJudgeSession(forceRefresh: Boolean = false) {
    if (!forceRefresh && judgeSessionActivated) return
    val response =
        LocalUpstreamClientProvider.shared().get(judgeServiceLoginUrl()) {
          applyJudgeBrowserHeaders()
        }
    val body = response.bodyAsText()
    if (isLocalJudgeSessionExpired(response, body)) {
      throw LocalJudgeAuthenticationException("希冀登录状态异常，请重新登录后重试")
    }
    if (response.status != HttpStatusCode.OK) {
      throw ApiCallException("希冀服务暂时不可用，请稍后重试", response.status, "judge_error")
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
    val response =
        LocalUpstreamClientProvider.shared().get(localUpstreamUrl(url)) {
          applyJudgeBrowserHeaders()
        }
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

  companion object {
    private const val BASE_URL = "https://judge.buaa.edu.cn"
    private const val DEFAULT_RETRY_COUNT = 3
  }
}

private fun judgeServiceLoginUrl(): String =
    localUpstreamUrl(JUDGE_SERVICE_LOGIN_URL)

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

private class LocalJudgeAuthenticationException(message: String) : RuntimeException(message)

private data class LocalJudgeCourseRaw(
    val courseId: String,
    val courseName: String,
)

private data class LocalJudgeAssignmentRaw(
    val assignmentId: String,
    val courseId: String,
    val courseName: String,
    val title: String,
)

private object LocalJudgeHtmlParsers {
  private val linkOptions = setOf(RegexOption.IGNORE_CASE, RegexOption.DOT_MATCHES_ALL)
  private val tagRegex = Regex("""<[^>]+>""")
  private val rowRegex = Regex("""<tr\b[^>]*>(.*?)</tr>""", linkOptions)
  private val cellRegex = Regex("""<(?:th|td)\b[^>]*>(.*?)</(?:th|td)>""", linkOptions)
  private val tableTagRegex = Regex("""</?table\b[^>]*>""", RegexOption.IGNORE_CASE)
  private val unsubmittedMarkers =
      listOf("还未提交代码", "未提交文件", "未提交答案", "未作答", "未提交")
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
            """<a\b[^>]*href\s*=\s*["'][^"']*courselist\.jsp\?courseID=(\d+)[^"']*["'][^>]*>(.*?)</a>""",
            linkOptions,
        )
    return regex
        .findAll(html)
        .mapNotNull { match ->
          val courseId = match.groupValues[1]
          if (courseId == "0") return@mapNotNull null
          val courseName = cleanText(stripTags(match.groupValues[2]))
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
            """<a\b[^>]*href\s*=\s*["']([^"']*assignID=(\d+)[^"']*)["'][^>]*>(.*?)</a>""",
            linkOptions,
        )
    return regex
        .findAll(html)
        .mapNotNull { match ->
          val href = match.groupValues[1]
          if (href.contains("problemContent") || href.contains("judgeDetails")) {
            return@mapNotNull null
          }
          val title = cleanText(stripTags(match.groupValues[3]))
          title.takeIf { it.isNotBlank() }?.let {
            LocalJudgeAssignmentRaw(
                assignmentId = match.groupValues[2],
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
        Regex("""共\s*(\d+)\s*道""").find(plainText)?.groupValues?.get(1)?.toIntOrNull()
            ?: 0
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
    val resolvedTotalProblems = if (totalProblems == 0 && problems.isNotEmpty()) problems.size else totalProblems
    val myScore =
        explicitMyScore
            ?: earnedScores.takeIf { it.isNotEmpty() }?.sum()?.let(::formatScore)
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
        submissionStatusText = submissionStatusText(status, submittedCount, resolvedTotalProblems, myScore, maxScore),
        problems = problems,
        contentPlainText = plainText.ifBlank { null },
    )
  }

  private data class ParsedProblem(
      val problem: JudgeProblemDto,
      val earnedScore: Double?,
  )

  private fun parseProblems(html: String): List<ParsedProblem> {
    return extractTopLevelTables(html)
        .flatMap { table ->
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
                  score = (earnedScore ?: if (status == JudgeSubmissionStatus.SUBMITTED) maxScore else null)
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
        listOf("填空题", "编程题", "文件上传题")
            .map { text.indexOf(it) }
            .filter { it >= 0 }
            .minOrNull()
            ?: text.length
    val choiceCount = Regex("""得分[：:]\s*[\d.]+""").findAll(text.substring(0, choiceEnd)).count()
    val fillStart = text.indexOf("填空题")
    val fillCount =
        if (fillStart >= 0) {
          val nextSection =
              listOf("编程题", "文件上传题")
                  .map { text.indexOf(it, fillStart + 2) }
                  .filter { it >= 0 }
                  .minOrNull()
                  ?: text.length
          Regex("""得分[：:]\s*[\d.]+""").findAll(text.substring(fillStart, nextSection)).count()
        } else {
          0
        }
    val programmingCount =
        text.indexOf("编程题").takeIf { it >= 0 }?.let {
          Regex("""最后一次提交时间""").findAll(text.substring(it)).count()
        } ?: 0
    val fileCount =
        text.indexOf("文件上传题").takeIf { it >= 0 }?.let {
          Regex("""初次提交时间""").findAll(text.substring(it)).count()
        } ?: 0
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
      cleanText(stripTags(html.replace(Regex("""<script\b.*?</script>""", linkOptions), " ")))

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
