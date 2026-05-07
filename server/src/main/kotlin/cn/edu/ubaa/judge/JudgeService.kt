package cn.edu.ubaa.judge

import cn.edu.ubaa.model.dto.JudgeAssignmentDetailDto
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailKeyDto
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailsResponse
import cn.edu.ubaa.model.dto.JudgeAssignmentSummaryDto
import cn.edu.ubaa.model.dto.JudgeAssignmentsResponse
import cn.edu.ubaa.utils.withUpstreamDeadline
import java.util.concurrent.ConcurrentHashMap
import kotlin.time.Clock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

/** 希冀作业业务服务。 */
internal class JudgeService(
    private val clientProvider: (String) -> JudgeClient = ::JudgeClient,
    private val nowProvider: () -> LocalDateTime = {
      Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    },
) {
  private data class CachedClient(
      val client: JudgeClient,
      @Volatile var lastAccessAt: Long,
      @Volatile var courses: CacheEntry<List<JudgeCourseRaw>>? = null,
      val assignmentsByCourse: ConcurrentHashMap<String, CacheEntry<List<JudgeAssignmentRaw>>> =
          ConcurrentHashMap(),
      val detailsByAssignment:
          ConcurrentHashMap<JudgeAssignmentDetailCacheKey, CacheEntry<JudgeAssignmentDetailDto>> =
          ConcurrentHashMap(),
  )

  private data class CacheEntry<T>(
      val value: T,
      val cachedAt: Long,
  )

  private data class JudgeAssignmentDetailCacheKey(
      val courseId: String,
      val assignmentId: String,
  )

  private data class JudgeAssignmentSummaryResult(
      val summaries: List<JudgeAssignmentSummaryDto>,
      val historicalCutoffCourseIds: Set<String>,
  )

  private val clientCache = ConcurrentHashMap<String, CachedClient>()

  suspend fun getAssignments(
      username: String,
      includeExpired: Boolean = false,
      skippedCourseIds: Set<String> = emptySet(),
  ): JudgeAssignmentsResponse {
    return withJudgeDeadline("希冀作业列表加载超时", ASSIGNMENTS_DEADLINE) {
      withCachedClient(username) { cached ->
        val courses = cached.getCourses()
        val courseResults =
            courses
                .filter { course -> includeExpired || course.courseId !in skippedCourseIds }
                .mapConcurrently(JUDGE_ASSIGNMENT_QUERY_CONCURRENCY) { course ->
                  cached.client.withIsolatedClient { worker ->
                    cached.getAssignmentSummaries(
                        course = course,
                        includeExpired = includeExpired,
                        worker = worker,
                    )
                  }
                }
        val historicalCutoffCourseIds =
            courseResults.flatMap { it.historicalCutoffCourseIds }.toSet()
        val assignments =
            courseResults
                .flatMap { it.summaries }
                .sortedWith(
                    compareBy<JudgeAssignmentSummaryDto> { it.dueTime ?: "9999-99-99 99:99:99" }
                        .thenBy { it.courseName }
                        .thenBy { it.title }
                )
        JudgeAssignmentsResponse(
            assignments = assignments,
            historicalCutoffCourseIds = historicalCutoffCourseIds.sorted(),
        )
      }
    }
  }

  suspend fun getAssignmentDetail(
      username: String,
      courseId: String,
      assignmentId: String,
  ): JudgeAssignmentDetailDto {
    return withJudgeDeadline("希冀作业详情加载超时") {
      withCachedClient(username) { cached ->
        getAssignmentDetailsInternal(
                cached,
                listOf(
                    JudgeAssignmentDetailKeyDto(courseId = courseId, assignmentId = assignmentId)
                ),
            )
            .firstOrNull() ?: throw JudgeResourceNotFoundException("希冀作业不存在或无权限访问")
      }
    }
  }

  suspend fun getAssignmentDetails(
      username: String,
      keys: List<JudgeAssignmentDetailKeyDto>,
  ): JudgeAssignmentDetailsResponse {
    return withJudgeDeadline("希冀作业详情加载超时") {
      withCachedClient(username) { cached ->
        JudgeAssignmentDetailsResponse(getAssignmentDetailsInternal(cached, normalizeKeys(keys)))
      }
    }
  }

  fun cleanupExpiredClients(maxIdleMillis: Long = DEFAULT_MAX_IDLE_MILLIS): Int {
    val cutoff = System.currentTimeMillis() - maxIdleMillis
    var removed = 0
    for ((username, cached) in clientCache.entries.toList()) {
      if (cached.lastAccessAt > cutoff) continue
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

  private suspend fun <T> withCachedClient(
      username: String,
      block: suspend (CachedClient) -> T,
  ): T {
    val cached = getCachedClient(username)
    cached.lastAccessAt = System.currentTimeMillis()
    return block(cached)
  }

  private fun getCachedClient(username: String): CachedClient {
    val now = System.currentTimeMillis()
    return clientCache.compute(username) { _, existing ->
      existing?.also { it.lastAccessAt = now } ?: CachedClient(clientProvider(username), now)
    }!!
  }

  private suspend fun <T> withJudgeDeadline(
      message: String,
      timeout: Duration = DEFAULT_UPSTREAM_DEADLINE,
      block: suspend () -> T,
  ): T {
    return withUpstreamDeadline(timeout, message, "judge_timeout", block)
  }

  private suspend fun getAssignmentDetailsInternal(
      cached: CachedClient,
      keys: List<JudgeAssignmentDetailKeyDto>,
  ): List<JudgeAssignmentDetailDto> {
    if (keys.isEmpty()) return emptyList()
    val courses = cached.getCourses().associateBy { it.courseId }
    return keys
        .groupBy { it.courseId }
        .entries
        .mapConcurrently(JUDGE_ASSIGNMENT_QUERY_CONCURRENCY) { (courseId, courseKeys) ->
          val course = courses[courseId] ?: throw JudgeResourceNotFoundException("希冀课程不存在或无权限访问")
          cached.client.withIsolatedClient { worker ->
            val assignments =
                cached
                    .getAssignments(course) { worker.getAssignments(course) }
                    .associateBy { it.assignmentId }
            courseKeys.map { key ->
              val assignment =
                  assignments[key.assignmentId]
                      ?: throw JudgeResourceNotFoundException("希冀作业不存在或无权限访问")
              val cacheKey =
                  JudgeAssignmentDetailCacheKey(
                      courseId = assignment.courseId,
                      assignmentId = assignment.assignmentId,
                  )
              cached.getDetail(cacheKey) {
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
  }

  private suspend fun CachedClient.getAssignmentSummaries(
      course: JudgeCourseRaw,
      includeExpired: Boolean,
      worker: JudgeClient,
  ): JudgeAssignmentSummaryResult {
    val assignments = getAssignments(course) { worker.getAssignments(course) }
    val summaries = mutableListOf<JudgeAssignmentSummaryDto>()
    var reachedHistoricalCutoff = false
    for (assignment in assignments) {
      val cacheKey =
          JudgeAssignmentDetailCacheKey(
              courseId = assignment.courseId,
              assignmentId = assignment.assignmentId,
          )
      val detail =
          getDetail(cacheKey) {
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
    return JudgeAssignmentSummaryResult(
        summaries = summaries,
        historicalCutoffCourseIds =
            if (reachedHistoricalCutoff) setOf(course.courseId) else emptySet(),
    )
  }

  private suspend fun CachedClient.getCourses(): List<JudgeCourseRaw> {
    val now = System.currentTimeMillis()
    courses
        ?.takeIf { it.isFresh(COURSES_AND_ASSIGNMENTS_TTL_MILLIS, now) }
        ?.let {
          return it.value
        }
    val fetched = client.getCourses()
    if (fetched.isNotEmpty()) {
      courses = CacheEntry(fetched, now)
    }
    return fetched
  }

  private suspend fun CachedClient.getAssignments(
      course: JudgeCourseRaw,
      fetch: suspend () -> List<JudgeAssignmentRaw>,
  ): List<JudgeAssignmentRaw> {
    val now = System.currentTimeMillis()
    assignmentsByCourse[course.courseId]
        ?.takeIf { it.isFresh(COURSES_AND_ASSIGNMENTS_TTL_MILLIS, now) }
        ?.let {
          return it.value
        }
    val fetched = fetch()
    if (fetched.isNotEmpty()) {
      assignmentsByCourse[course.courseId] = CacheEntry(fetched, now)
    } else {
      assignmentsByCourse.remove(course.courseId)
    }
    return fetched
  }

  private suspend fun CachedClient.getDetail(
      key: JudgeAssignmentDetailCacheKey,
      fetch: suspend () -> JudgeAssignmentDetailDto,
  ): JudgeAssignmentDetailDto {
    val now = System.currentTimeMillis()
    detailsByAssignment[key]
        ?.takeIf { it.isFresh(DETAIL_TTL_MILLIS, now) }
        ?.let {
          return it.value
        }
    val fetched = fetch()
    detailsByAssignment[key] = CacheEntry(fetched, now)
    return fetched
  }

  private fun <T> CacheEntry<T>.isFresh(ttlMillis: Long, now: Long): Boolean =
      now - cachedAt < ttlMillis

  private fun normalizeKeys(
      keys: List<JudgeAssignmentDetailKeyDto>
  ): List<JudgeAssignmentDetailKeyDto> =
      keys
          .filter { it.courseId.isNotBlank() && it.assignmentId.isNotBlank() }
          .distinctBy { it.courseId to it.assignmentId }

  private fun JudgeAssignmentDetailDto.startedBeforeSixMonthCutoff(): Boolean {
    val startAt = parseJudgeDateTime(startTime) ?: return false
    return startAt < nowProvider().minusJudgeMonths(6)
  }

  companion object {
    private const val DEFAULT_MAX_IDLE_MILLIS = 30 * 60 * 1000L
    private const val JUDGE_ASSIGNMENT_QUERY_CONCURRENCY = 4
    private const val COURSES_AND_ASSIGNMENTS_TTL_MILLIS = 5 * 60 * 1000L
    private const val DETAIL_TTL_MILLIS = 2 * 60 * 1000L
    private val DEFAULT_UPSTREAM_DEADLINE = 9.seconds
    private val ASSIGNMENTS_DEADLINE = 30.seconds
  }
}

private fun parseJudgeDateTime(value: String?): LocalDateTime? {
  val normalized = value?.trim()?.takeIf { it.isNotEmpty() }?.replace(" ", "T") ?: return null
  return runCatching { LocalDateTime.parse(normalized) }.getOrNull()
}

private fun LocalDateTime.minusJudgeMonths(months: Int): LocalDateTime {
  var targetYear = year
  var targetMonth = month.ordinal + 1 - months
  while (targetMonth <= 0) {
    targetMonth += 12
    targetYear--
  }
  val targetDay = minOf(day, judgeDaysInMonth(targetYear, targetMonth))
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

private fun judgeDaysInMonth(year: Int, month: Int): Int =
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
      2 -> if (judgeIsLeapYear(year)) 29 else 28
      else -> 30
    }

private fun judgeIsLeapYear(year: Int): Boolean =
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

private suspend fun <T, R> Iterable<T>.mapConcurrently(
    concurrency: Int,
    transform: suspend (T) -> R,
): List<R> = coroutineScope {
  val semaphore = Semaphore(concurrency)
  map { item -> async { semaphore.withPermit { transform(item) } } }.awaitAll()
}

internal object GlobalJudgeService {
  val instance: JudgeService by lazy { JudgeService() }
}
