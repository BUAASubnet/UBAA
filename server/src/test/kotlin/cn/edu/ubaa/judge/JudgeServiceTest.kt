package cn.edu.ubaa.judge

import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.runBlocking

class JudgeServiceTest {
  @Test
  fun `get assignments aggregates courses and sorts by due time`() = runBlocking {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })

    val response = service.getAssignments("24182104")

    assertEquals(2, response.assignments.size)
    assertEquals(listOf("102", "101"), response.assignments.map { it.assignmentId })
    assertEquals(listOf("算法设计", "软件工程"), response.assignments.map { it.courseName })
    assertEquals(JudgeSubmissionStatus.SUBMITTED, response.assignments.first().submissionStatus)
    assertEquals(JudgeSubmissionStatus.PARTIAL, response.assignments.last().submissionStatus)
    assertEquals(1, fakeClient.courseCalls)
    assertEquals(2, fakeClient.assignmentCalls)
    assertEquals(2, fakeClient.detailCalls)
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
  fun `cleanup expired clients closes removed clients only`() {
    val fakeClient = FakeJudgeClient()
    val service = JudgeService(clientProvider = { fakeClient })

    runBlocking { service.getAssignments("24182104") }

    assertEquals(1, service.cacheSize())
    assertEquals(1, service.cleanupExpiredClients(maxIdleMillis = 0))
    assertEquals(0, service.cacheSize())
    assertEquals(1, fakeClient.closeCalls)
  }

  private class FakeJudgeClient :
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
    var closeCalls = 0

    override suspend fun getCourses(): List<JudgeCourseRaw> {
      courseCalls++
      return listOf(
          JudgeCourseRaw(courseId = "1", courseName = "软件工程"),
          JudgeCourseRaw("2", "算法设计"),
      )
    }

    override suspend fun getAssignments(course: JudgeCourseRaw): List<JudgeAssignmentRaw> {
      assignmentCalls++
      return when (course.courseId) {
        "1" -> listOf(JudgeAssignmentRaw("101", "1", "软件工程", "设计作业"))
        "2" -> listOf(JudgeAssignmentRaw("102", "2", "算法设计", "编程作业"))
        else -> emptyList()
      }
    }

    override suspend fun getAssignmentDetail(
        courseId: String,
        courseName: String,
        assignmentId: String,
        title: String,
    ): JudgeAssignmentParsedDetail {
      detailCalls++
      return JudgeParsers.parseAssignmentDetail(
          html =
              if (assignmentId == "101") {
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
              } else {
                """
                <html><body>
                  作业时间：2026-04-10 08:00:00 至 2026-04-18 23:00:00
                  作业满分： 20.00 ，共 1道 题 总分：20.00
                  <table><tbody>
                    <tr><th>1.</th><td>程序题</td><td>20.00</td><td>最后一次提交时间：2026-04-17 12:00:00 得分：20.00</td></tr>
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

    override fun close() {
      closeCalls++
    }
  }
}
