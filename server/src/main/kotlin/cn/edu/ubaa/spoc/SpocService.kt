package cn.edu.ubaa.spoc

import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.SpocAssignmentDetailDto
import cn.edu.ubaa.model.dto.SpocAssignmentSummaryDto
import cn.edu.ubaa.model.dto.SpocAssignmentsResponse
import cn.edu.ubaa.utils.withUpstreamDeadline
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration.Companion.seconds
import org.slf4j.LoggerFactory

/** SPOC 作业业务服务。 */
internal class SpocService(private val clientProvider: (String) -> SpocClient = ::SpocClient) {
  private data class CachedClient(
      val client: SpocClient,
      @Volatile var lastAccessAt: Long,
  )

  private val clientCache = ConcurrentHashMap<String, CachedClient>()
  private val log = LoggerFactory.getLogger(SpocService::class.java)

  suspend fun getAssignments(username: String): SpocAssignmentsResponse {
    return withSpocDeadline("SPOC 作业列表加载超时") {
      val client = getClient(username)
      val term = client.getCurrentTerm()
      val termCode = term.mrxq ?: throw SpocException("无法获取 SPOC 当前学期代码")
      val courseMap =
          try {
            client.getCourses(termCode).associateBy { it.kcid }
          } catch (e: Exception) {
            // Degrade gracefully: assignments can still be shown even if course metadata is
            // missing.
            AppObservability.recordFallbackEvent(
                "spoc",
                "list_assignments",
                "spoc_missing_course_metadata",
            )
            log.warn(
                "Failed to fetch SPOC courses for username={} termCode={}, continuing without course metadata",
                username,
                termCode,
                e,
            )
            emptyMap()
          }
      val rawAssignments = client.getAllAssignments(termCode)

      val assignments =
          rawAssignments
              .map { assignment ->
                val course = assignment.sskcid?.let { courseMap[it] }
                val status =
                    SpocParsers.mapSubmissionStatus(
                        rawStatus = assignment.tjzt,
                        hasContent = !assignment.tjzt.isNullOrBlank(),
                    )
                SpocAssignmentSummaryDto(
                    assignmentId = assignment.zyid,
                    courseId = assignment.sskcid.orEmpty(),
                    courseName = assignment.kcmc ?: course?.kcmc.orEmpty(),
                    teacherName = course?.skjs,
                    title = assignment.zymc,
                    startTime = SpocParsers.normalizeDateTime(assignment.zykssj),
                    dueTime = SpocParsers.normalizeDateTime(assignment.zyjzsj),
                    score = SpocParsers.normalizeScore(assignment.mf),
                    submissionStatus = status,
                    submissionStatusText =
                        SpocParsers.submissionStatusText(status, assignment.tjzt),
                )
              }
              .sortedWith(
                  compareBy<SpocAssignmentSummaryDto> { it.dueTime ?: "9999-99-99 99:99:99" }
                      .thenBy { it.courseName }
                      .thenBy { it.title }
              )

      SpocAssignmentsResponse(
          termCode = termCode,
          termName = term.dqxq,
          assignments = assignments,
      )
    }
  }

  suspend fun getAssignmentDetail(username: String, assignmentId: String): SpocAssignmentDetailDto {
    return withSpocDeadline("SPOC 作业详情加载超时") {
      val summary =
          getAssignments(username).assignments.firstOrNull { it.assignmentId == assignmentId }
              ?: throw SpocException("未找到指定的 SPOC 作业")

      val client = getClient(username)
      val detail = client.getAssignmentDetail(assignmentId)
      val submission = runCatching { client.getSubmission(assignmentId) }.getOrNull()
      val hasSubmission = submission != null
      val status = SpocParsers.mapSubmissionStatus(submission?.tjzt, hasSubmission)

      summary
          .copy(
              score = SpocParsers.normalizeScore(detail.zyfs) ?: summary.score,
              startTime = SpocParsers.normalizeDateTime(detail.zykssj) ?: summary.startTime,
              dueTime = SpocParsers.normalizeDateTime(detail.zyjzsj) ?: summary.dueTime,
              submissionStatus = status,
              submissionStatusText = SpocParsers.submissionStatusText(status, submission?.tjzt),
          )
          .toDetail(
              contentPlainText = SpocParsers.toPlainText(detail.zynr),
              contentHtml = detail.zynr,
              submittedAt = SpocParsers.normalizeDateTime(submission?.tjsj),
          )
    }
  }

  fun cleanupExpiredClients(maxIdleMillis: Long = DEFAULT_MAX_IDLE_MILLIS): Int {
    val cutoff = System.currentTimeMillis() - maxIdleMillis
    var removed = 0
    for ((username, cached) in clientCache.entries.toList()) {
      if (cached.lastAccessAt >= cutoff) continue
      if (!clientCache.remove(username, cached)) continue
      cached.client.close()
      removed++
    }
    return removed
  }

  fun cacheSize(): Int = clientCache.size

  fun clearCache() {
    clientCache.values.forEach { it.client.close() }
    clientCache.clear()
  }

  private fun getClient(username: String): SpocClient {
    val now = System.currentTimeMillis()
    return clientCache
        .compute(username) { _, existing ->
          existing?.also { it.lastAccessAt = now } ?: CachedClient(clientProvider(username), now)
        }!!
        .client
  }

  companion object {
    private const val DEFAULT_MAX_IDLE_MILLIS = 30 * 60 * 1000L
  }

  private suspend fun <T> withSpocDeadline(message: String, block: suspend () -> T): T {
    return withUpstreamDeadline(9.seconds, message, "spoc_timeout", block)
  }
}

internal object GlobalSpocService {
  val instance: SpocService by lazy { SpocService() }
}
