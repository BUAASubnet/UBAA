package cn.edu.ubaa.judge

import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeProblemDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import org.jsoup.Jsoup
import org.jsoup.nodes.Element

internal open class JudgeException(message: String, cause: Throwable? = null) :
    RuntimeException(message, cause)

internal class JudgeAuthenticationException(message: String) : JudgeException(message)

internal typealias JudgeAssignmentParsedDetail = JudgeAssignmentDetailDto

internal data class JudgeCourseRaw(
    val courseId: String,
    val courseName: String,
)

internal data class JudgeAssignmentRaw(
    val assignmentId: String,
    val courseId: String,
    val courseName: String,
    val title: String,
)

internal object JudgeParsers {
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

  fun parseCourses(html: String): List<JudgeCourseRaw> {
    val document = Jsoup.parse(html)
    return document
        .select("a[href*=courselist.jsp?courseID=]")
        .mapNotNull { anchor ->
          val courseId =
              Regex("""courseID=(\d+)""").find(anchor.attr("href"))?.groupValues?.get(1)
                  ?: return@mapNotNull null
          if (courseId == "0") return@mapNotNull null
          val courseName = cleanText(anchor.text())
          courseName.takeIf { it.isNotBlank() }?.let { JudgeCourseRaw(courseId, it) }
        }
        .distinctBy { it.courseId }
  }

  fun parseAssignments(
      html: String,
      course: JudgeCourseRaw,
  ): List<JudgeAssignmentRaw> {
    val document = Jsoup.parse(html)
    return document
        .select("a[href*=assignID=]")
        .mapNotNull { anchor ->
          val href = anchor.attr("href")
          if (href.contains("problemContent") || href.contains("judgeDetails")) {
            return@mapNotNull null
          }
          val assignmentId =
              Regex("""assignID=(\d+)""").find(href)?.groupValues?.get(1)
                  ?: return@mapNotNull null
          val title = cleanText(anchor.text())
          title.takeIf { it.isNotBlank() }?.let {
            JudgeAssignmentRaw(
                assignmentId = assignmentId,
                courseId = course.courseId,
                courseName = course.courseName,
                title = it,
            )
          }
        }
        .distinctBy { it.assignmentId }
  }

  fun parseAssignmentDetail(
      html: String,
      courseId: String,
      courseName: String,
      assignmentId: String,
      title: String,
  ): JudgeAssignmentParsedDetail {
    val document = Jsoup.parse(html)
    val plainText = cleanText(document.text())
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
    val parsedProblems = parseProblems(document.body())
    val problems = parsedProblems.map { it.problem }
    val earnedScores = parsedProblems.mapNotNull { it.earnedScore }
    val submittedCount =
        if (problems.isNotEmpty()) {
          problems.count { it.status != JudgeSubmissionStatus.UNSUBMITTED }
        } else {
          estimateSubmittedCount(plainText)
        }
    val resolvedTotalProblems = if (totalProblems == 0 && problems.isNotEmpty()) problems.size else totalProblems
    val myScore =
        explicitMyScore
            ?: earnedScores.takeIf { it.isNotEmpty() }?.sum()?.let(::formatScore)
    val normalizedMaxScore = maxScore?.toDoubleOrNull()?.let(::formatScore) ?: maxScore
    val normalizedMyScore = myScore?.toDoubleOrNull()?.let(::formatScore) ?: myScore
    val status = resolveStatus(resolvedTotalProblems, submittedCount)

    return JudgeAssignmentDetailDto(
        courseId = courseId,
        courseName = courseName,
        assignmentId = assignmentId,
        title = title,
        startTime = startAndEnd?.groupValues?.get(1)?.let(::normalizeDateTime),
        dueTime = startAndEnd?.groupValues?.get(2)?.let(::normalizeDateTime),
        maxScore = normalizedMaxScore,
        myScore = normalizedMyScore,
        totalProblems = resolvedTotalProblems,
        submittedCount = submittedCount,
        submissionStatus = status,
        submissionStatusText =
            submissionStatusText(
                status = status,
                submittedCount = submittedCount,
                totalProblems = resolvedTotalProblems,
                myScore = normalizedMyScore,
                maxScore = normalizedMaxScore,
            ),
        problems = problems,
        contentPlainText = plainText.ifBlank { null },
    )
  }

  private data class ParsedProblem(
      val problem: JudgeProblemDto,
      val earnedScore: Double?,
  )

  private fun parseProblems(root: Element): List<ParsedProblem> {
    return root
        .select("table")
        .filterNot { table -> table.parents().any { it.tagName().equals("table", ignoreCase = true) } }
        .flatMap { table ->
          val bodies = table.children().filter { it.tagName().equals("tbody", ignoreCase = true) }
          val containers = bodies.ifEmpty { listOf(table) }
          containers.flatMap { container ->
            container
                .children()
                .filter { it.tagName().equals("tr", ignoreCase = true) }
                .mapNotNull(::parseProblemFromRow)
          }
        }
  }

  private fun parseProblemFromRow(row: Element): ParsedProblem? {
    val cells =
        row
            .children()
            .filter {
              it.tagName().equals("th", ignoreCase = true) ||
                  it.tagName().equals("td", ignoreCase = true)
            }
            .map { cleanText(it.text()) }

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
                      (earnedScore ?: if (status == JudgeSubmissionStatus.SUBMITTED) maxScore else null)
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

  private fun cleanText(value: String): String =
      value.replace('\u00a0', ' ').replace(Regex("""\s+"""), " ").trim()
}

internal fun JudgeAssignmentDetailDto.toSummary(): JudgeAssignmentSummaryDto =
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
