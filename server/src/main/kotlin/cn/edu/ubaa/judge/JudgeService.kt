package cn.edu.ubaa.judge

import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeAssignmentsResponse
import cn.edu.ubaa.utils.withUpstreamDeadline
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Duration.Companion.seconds

/** 希冀作业业务服务。 */
internal class JudgeService(private val clientProvider: (String) -> JudgeClient = ::JudgeClient) {
  private data class CachedClient(
      val client: JudgeClient,
      @Volatile var lastAccessAt: Long,
  )

  private val clientCache = ConcurrentHashMap<String, CachedClient>()

  suspend fun getAssignments(username: String): JudgeAssignmentsResponse {
    return withJudgeDeadline("希冀作业列表加载超时") {
      val client = getClient(username)
      val assignments =
          client
              .getCourses()
              .flatMap { course ->
                client.getAssignments(course).map { assignment ->
                  client
                      .getAssignmentDetail(
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
      JudgeAssignmentsResponse(assignments)
    }
  }

  suspend fun getAssignmentDetail(
      username: String,
      courseId: String,
      assignmentId: String,
  ): JudgeAssignmentDetailDto {
    return withJudgeDeadline("希冀作业详情加载超时") {
      val client = getClient(username)
      val course = client.getCourses().firstOrNull { it.courseId == courseId }
      val courseName = course?.courseName.orEmpty()
      val assignment =
          course?.let {
            client.getAssignments(it).firstOrNull { raw -> raw.assignmentId == assignmentId }
          }

      client.getAssignmentDetail(
          courseId = courseId,
          courseName = assignment?.courseName ?: courseName,
          assignmentId = assignmentId,
          title = assignment?.title ?: assignmentId,
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

  private fun getClient(username: String): JudgeClient {
    val now = System.currentTimeMillis()
    return clientCache
        .compute(username) { _, existing ->
          existing?.also { it.lastAccessAt = now } ?: CachedClient(clientProvider(username), now)
        }!!
        .client
  }

  private suspend fun <T> withJudgeDeadline(message: String, block: suspend () -> T): T {
    return withUpstreamDeadline(9.seconds, message, "judge_timeout", block)
  }

  companion object {
    private const val DEFAULT_MAX_IDLE_MILLIS = 30 * 60 * 1000L
  }
}

internal object GlobalJudgeService {
  val instance: JudgeService by lazy { JudgeService() }
}
