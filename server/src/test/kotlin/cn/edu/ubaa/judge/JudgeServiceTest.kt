package cn.edu.ubaa.judge

import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailKeyDto
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.datetime.LocalDateTime

class JudgeServiceTest {
  @Test
  fun `get assignments returns detail-backed summaries`() = runBlocking {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })

    val response = service.getAssignments("24182104")

    assertEquals(2, response.assignments.size)
    assertEquals(listOf("102", "101"), response.assignments.map { it.assignmentId })
    assertEquals(listOf("算法设计", "软件工程"), response.assignments.map { it.courseName })
    assertEquals(
        listOf(JudgeSubmissionStatus.UNSUBMITTED, JudgeSubmissionStatus.PARTIAL),
        response.assignments.map { it.submissionStatus },
    )
    assertEquals(1, fakeClient.courseCalls)
    assertEquals(2, fakeClient.assignmentCalls)
    assertEquals(2, fakeClient.detailCalls)
  }

  @Test
  fun `get assignments fetches details per course and stops after six month old assignment`() =
      runBlocking {
        val fakeClient = FakeJudgeClient(oldAssignmentFixture = true)
        val service =
            JudgeService(
                clientProvider = { fakeClient },
                nowProvider = { LocalDateTime.parse("2026-05-01T12:00:00") },
            )

        val response = service.getAssignments("24182104", includeExpired = false)

        assertEquals(listOf("102", "101"), response.assignments.map { it.assignmentId })
        assertEquals(
            listOf(JudgeSubmissionStatus.UNSUBMITTED, JudgeSubmissionStatus.PARTIAL),
            response.assignments.map { it.submissionStatus },
        )
        assertTrue(
            fakeClient.detailRequestIds.containsAll(listOf("101", "102", "103")),
            "expected recent assignments and the old sentinel to be inspected",
        )
        assertTrue(
            "104" !in fakeClient.detailRequestIds,
            "expected course traversal to stop before assignments after the old sentinel",
        )
        assertEquals(listOf("1"), response.historicalCutoffCourseIds)
      }

  @Test
  fun `get assignments includes old assignments when expired assignments are requested`() =
      runBlocking {
        val fakeClient = FakeJudgeClient(oldAssignmentFixture = true)
        val service =
            JudgeService(
                clientProvider = { fakeClient },
                nowProvider = { LocalDateTime.parse("2026-05-01T12:00:00") },
            )

        val response = service.getAssignments("24182104", includeExpired = true)

        assertEquals(
            listOf("104", "103", "102", "101"),
            response.assignments.map { it.assignmentId },
        )
        assertTrue("104" in fakeClient.detailRequestIds)
      }

  @Test
  fun `get assignments skips client provided courses without fetching their assignments`() =
      runBlocking {
        val fakeClient = FakeJudgeClient(oldAssignmentFixture = true)
        val service =
            JudgeService(
                clientProvider = { fakeClient },
                nowProvider = { LocalDateTime.parse("2026-05-01T12:00:00") },
            )

        val response =
            service.getAssignments(
                username = "24182104",
                includeExpired = false,
                skippedCourseIds = setOf("1"),
            )

        assertEquals(listOf("102"), response.assignments.map { it.assignmentId })
        assertEquals(listOf("2"), fakeClient.assignmentRequestCourseIds)
        assertEquals(listOf("102"), fakeClient.detailRequestIds)
      }

  @Test
  fun `get assignment detail keeps problem list`() = runBlocking {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })

    val detail = service.getAssignmentDetail("24182104", "1", "101")

    assertEquals("101", detail.assignmentId)
    assertEquals("软件工程", detail.courseName)
    assertEquals("设计作业", detail.title)
    assertEquals("100", detail.maxScore)
    assertEquals(2, detail.totalProblems)
    assertEquals(1, detail.submittedCount)
    assertEquals(listOf("设计说明", "用例设计"), detail.problems.map { it.name })
  }

  @Test
  fun `get assignment detail rejects course outside current user courses`() = runBlocking {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })

    assertFailsWith<JudgeException> { service.getAssignmentDetail("24182104", "missing", "101") }

    assertEquals(1, fakeClient.courseCalls)
    assertEquals(0, fakeClient.assignmentCalls)
    assertEquals(0, fakeClient.detailCalls)
  }

  @Test
  fun `get assignment detail rejects assignment outside selected course`() = runBlocking {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })

    assertFailsWith<JudgeException> { service.getAssignmentDetail("24182104", "1", "missing") }

    assertEquals(1, fakeClient.courseCalls)
    assertEquals(1, fakeClient.assignmentCalls)
    assertEquals(0, fakeClient.detailCalls)
  }

  @Test
  fun `assignment course queries run concurrently per user`() = runBlocking {
    val fakeClient = FakeJudgeClient(delayOperations = true)
    val service = JudgeService(clientProvider = { fakeClient })

    service.getAssignments("24182104")

    assertTrue(fakeClient.maxActiveCalls > 1, "expected concurrent judge course queries")
  }

  @Test
  fun `batch assignment detail reuses course queries and caches repeated details`() = runBlocking {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })
    val keys =
        listOf(
            JudgeAssignmentDetailKeyDto(courseId = "1", assignmentId = "101"),
            JudgeAssignmentDetailKeyDto(courseId = "1", assignmentId = "101"),
            JudgeAssignmentDetailKeyDto(courseId = "2", assignmentId = "102"),
        )

    val first = service.getAssignmentDetails("24182104", keys)
    val second = service.getAssignmentDetails("24182104", keys)

    assertEquals(listOf("101", "102"), first.details.map { it.assignmentId })
    assertEquals(listOf("101", "102"), second.details.map { it.assignmentId })
    assertEquals(1, fakeClient.courseCalls)
    assertEquals(2, fakeClient.assignmentCalls)
    assertEquals(2, fakeClient.detailCalls)
  }

  @Test
  fun `empty assignment list is not cached so later refresh can recover`() = runBlocking {
    val fakeClient = FakeJudgeClient(emptyFirstAssignmentList = true)
    val service = JudgeService(clientProvider = { fakeClient })

    val first = service.getAssignments("24182104")
    val second = service.getAssignments("24182104")

    assertEquals(emptyList(), first.assignments)
    assertEquals(listOf("102", "101"), second.assignments.map { it.assignmentId })
    assertTrue(fakeClient.assignmentCalls > 2, "expected second request to refetch empty lists")
  }

  @Test
  fun `cleanup expired clients closes removed clients only`() {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })

    runBlocking { service.getAssignments("24182104") }

    assertEquals(1, service.cacheSize())
    assertEquals(1, service.cleanupExpiredClients(maxIdleMillis = 0))
    assertEquals(0, service.cacheSize())
    assertEquals(1, fakeClient.closeCalls)
  }

  private class FakeJudgeClient(
      private val delayOperations: Boolean = false,
      private val emptyFirstAssignmentList: Boolean = false,
      private val oldAssignmentFixture: Boolean = false,
  ) :
      JudgeClient(
          username = "24182104",
          sessionManager =
              SessionManager(
                  sessionStore = InMemorySessionStore(),
                  cookieStorageFactory = InMemoryCookieStorageFactory(),
              ),
      ) {
    var courseCalls = 0
    var assignmentCalls = 0
    var detailCalls = 0
    val assignmentRequestCourseIds = mutableListOf<String>()
    val detailRequestIds = mutableListOf<String>()
    var closeCalls = 0
    var maxActiveCalls = 0
      private set

    private var activeCalls = 0
    private var shouldReturnEmptyAssignments = emptyFirstAssignmentList

    override suspend fun getCourses(): List<JudgeCourseRaw> {
      return tracked {
        courseCalls++
        listOf(
            JudgeCourseRaw(courseId = "1", courseName = "软件工程"),
            JudgeCourseRaw("2", "算法设计"),
        )
      }
    }

    override suspend fun getAssignments(course: JudgeCourseRaw): List<JudgeAssignmentRaw> {
      return tracked {
        assignmentCalls++
        assignmentRequestCourseIds += course.courseId
        if (shouldReturnEmptyAssignments) {
          if (assignmentCalls >= 2) {
            shouldReturnEmptyAssignments = false
          }
          return@tracked emptyList()
        }
        when (course.courseId) {
          "1" ->
              if (oldAssignmentFixture) {
                listOf(
                    JudgeAssignmentRaw("101", "1", "软件工程", "设计作业"),
                    JudgeAssignmentRaw("103", "1", "软件工程", "历史作业"),
                    JudgeAssignmentRaw("104", "1", "软件工程", "更早作业"),
                )
              } else {
                listOf(JudgeAssignmentRaw("101", "1", "软件工程", "设计作业"))
              }
          "2" -> listOf(JudgeAssignmentRaw("102", "2", "算法设计", "编程作业"))
          else -> emptyList()
        }
      }
    }

    override suspend fun getAssignmentDetail(
        courseId: String,
        courseName: String,
        assignmentId: String,
        title: String,
    ): JudgeAssignmentParsedDetail {
      return tracked {
        detailCalls++
        detailRequestIds += assignmentId
        JudgeParsers.parseAssignmentDetail(
            html =
                when (assignmentId) {
                  "101" ->
                      """
                <html><body>
                  作业时间：2026-04-20 19:00:00 至 2026-05-03 23:00:00
                  作业满分： 100.00 ，共 2道 题
                  <table><tbody>
                    <tr><th>1.</th><td>设计说明</td><td>60.00</td><td>初次提交时间: 2026-04-17 12:24:26</td></tr>
                    <tr><th>2.</th><td>用例设计</td><td>40.00</td><td>未提交答案</td></tr>
                  </tbody></table>
                </body></html>
                """
                  "102" ->
                      """
                <html><body>
                  作业时间：2026-04-10 08:00:00 至 2026-04-18 23:00:00
                  作业满分： 20.00 ，共 1道 题
                  <table><tbody>
                    <tr><th>1.</th><td>程序题</td><td>20.00</td><td>未提交答案</td></tr>
                  </tbody></table>
                </body></html>
                """
                  "103" ->
                      """
                <html><body>
                  作业时间：2025-10-30 08:00:00 至 2025-11-10 23:00:00
                  作业满分： 10.00 ，共 1道 题 总分：10.00
                  <table><tbody>
                    <tr><th>1.</th><td>历史题</td><td>10.00</td><td>最后一次提交时间：2025-11-01 12:00:00 得分：10.00</td></tr>
                  </tbody></table>
                </body></html>
                """
                  else ->
                      """
                <html><body>
                  作业时间：2025-09-01 08:00:00 至 2025-09-10 23:00:00
                  作业满分： 10.00 ，共 1道 题 总分：10.00
                  <table><tbody>
                    <tr><th>1.</th><td>更早题</td><td>10.00</td><td>最后一次提交时间：2025-09-02 12:00:00 得分：10.00</td></tr>
                  </tbody></table>
                </body></html>
                """
                },
            courseId = courseId,
            courseName = courseName,
            assignmentId = assignmentId,
            title = title,
        )
      }
    }

    override fun close() {
      closeCalls++
    }

    override suspend fun <T> withIsolatedClient(block: suspend (JudgeClient) -> T): T {
      return block(this)
    }

    private suspend fun <T> tracked(block: () -> T): T {
      if (!delayOperations) return block()
      activeCalls++
      maxActiveCalls = maxOf(maxActiveCalls, activeCalls)
      delay(20)
      return try {
        block()
      } finally {
        activeCalls--
      }
    }
  }
}
