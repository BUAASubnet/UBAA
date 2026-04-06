package cn.edu.ubaa.spoc

import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.model.dto.SpocSubmissionStatus
import io.micrometer.prometheusmetrics.PrometheusConfig
import io.micrometer.prometheusmetrics.PrometheusMeterRegistry
import kotlin.test.Test
import kotlin.test.assertContains
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class SpocServiceTest {

  @Test
  fun `get assignments uses paged list status without per item submission lookup`() = runBlocking {
    val fakeClient = FakeSpocClient()
    val service = SpocService(clientProvider = { fakeClient })

    val response = service.getAssignments("24182104")

    assertEquals("2025-20262", response.termCode)
    assertEquals(2, response.assignments.size)
    assertEquals(0, fakeClient.submissionCalls)
    assertEquals(1, fakeClient.currentTermCalls)
    assertEquals(1, fakeClient.courseCalls)
    assertEquals(1, fakeClient.pagedAssignmentsCalls)

    val first = response.assignments.first()
    val second = response.assignments.last()

    assertEquals("操作系统", first.courseName)
    assertEquals("牛虹婷,王良", first.teacherName)
    assertEquals("关于Agentic Coding的思考", first.title)
    assertEquals("2026-03-04 00:00:00", first.startTime)
    assertEquals("2026-03-11 23:59:00", first.dueTime)
    assertEquals("0", first.score)
    assertEquals(SpocSubmissionStatus.UNSUBMITTED, first.submissionStatus)

    assertEquals("lab0实验作业", second.title)
    assertEquals("100", second.score)
    assertEquals(SpocSubmissionStatus.SUBMITTED, second.submissionStatus)
  }

  @Test
  fun `get assignment detail keeps summary data and lets submit record override status`() =
      runBlocking {
        val fakeClient = FakeSpocClient()
        val service = SpocService(clientProvider = { fakeClient })

        val detail = service.getAssignmentDetail("24182104", "a1")

        assertEquals(1, fakeClient.submissionCalls)
        assertEquals("关于Agentic Coding的思考", detail.title)
        assertEquals("牛虹婷,王良", detail.teacherName)
        assertEquals("0", detail.score)
        assertEquals("2026-03-04 00:00:00", detail.startTime)
        assertEquals("2026-03-11 23:59:00", detail.dueTime)
        assertEquals(SpocSubmissionStatus.SUBMITTED, detail.submissionStatus)
        assertEquals("已提交", detail.submissionStatusText)
        assertEquals("2026-03-11 23:40:00", detail.submittedAt)
        assertEquals("请尽量给出自己的思考。", detail.contentPlainText)
      }

  @Test
  fun `get assignments tolerates course lookup failure with degraded metadata`() = runBlocking {
    val registry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
    AppObservability.initialize(registry)
    val fakeClient = CourseLookupFailureSpocClient()
    val service = SpocService(clientProvider = { fakeClient })

    try {
      val response = service.getAssignments("24182104")

      assertEquals(1, response.assignments.size)
      assertEquals("编译原理", response.assignments.first().courseName)
      assertEquals(null, response.assignments.first().teacherName)
      assertEquals(1, fakeClient.courseCalls)
      assertTrue(fakeClient.pagedAssignmentsCalls > 0)
      assertContains(
          registry.scrape(),
          "ubaa_fallback_events_total{feature=\"spoc\",operation=\"list_assignments\",reason=\"spoc_missing_course_metadata\"}",
      )
    } finally {
      AppObservability.reset(registry)
      registry.close()
    }
  }

  private class FakeSpocClient :
      SpocClient(
          username = "24182104",
          sessionManager =
              SessionManager(
                  sessionStore = InMemorySessionStore(),
                  cookieStorageFactory = InMemoryCookieStorageFactory(),
              ),
      ) {
    var currentTermCalls = 0
    var courseCalls = 0
    var pagedAssignmentsCalls = 0
    var submissionCalls = 0

    override suspend fun getCurrentTerm(): SpocCurrentTermContent {
      currentTermCalls++
      return SpocCurrentTermContent(dqxq = "2026年春季学期", mrxq = "2025-20262")
    }

    override suspend fun getCourses(termCode: String): List<SpocCourseRaw> {
      courseCalls++
      return listOf(SpocCourseRaw(kcid = "course-1", kcmc = "操作系统", skjs = "牛虹婷,王良"))
    }

    override suspend fun getAllAssignments(termCode: String): List<SpocPagedAssignmentRaw> {
      pagedAssignmentsCalls++
      return listOf(
          SpocPagedAssignmentRaw(
              zyid = "a1",
              tjzt = "未做",
              zyjzsj = "2026-03-11T15:59:00.000+00:00",
              zymc = "关于Agentic Coding的思考",
              zykssj = "2026-03-03T16:00:00.000+00:00",
              sskcid = "course-1",
              kcmc = "操作系统",
              mf = "满分:0",
          ),
          SpocPagedAssignmentRaw(
              zyid = "a2",
              tjzt = "已做",
              zyjzsj = "2026-03-19T16:00:00.000+00:00",
              zymc = "lab0实验作业",
              zykssj = "2026-03-16T16:00:00.000+00:00",
              sskcid = "course-1",
              kcmc = "操作系统",
              mf = "满分:100",
          ),
      )
    }

    override suspend fun getAssignmentDetail(assignmentId: String): SpocAssignmentDetailRaw {
      return SpocAssignmentDetailRaw(
          id = assignmentId,
          zymc = "关于Agentic Coding的思考",
          zynr = "<p>请尽量给出自己的思考。</p>",
          zykssj = "2026-03-03T16:00:00.000+00:00",
          zyjzsj = "2026-03-11T15:59:00.000+00:00",
          zyfs = "满分:0",
      )
    }

    override suspend fun getSubmission(assignmentId: String): SpocSubmissionRaw? {
      submissionCalls++
      return if (assignmentId == "a1") {
        SpocSubmissionRaw(tjzt = "1", tjsj = "2026-03-11T15:40:00.000+00:00")
      } else {
        null
      }
    }

    override fun close() = Unit
  }

  private class CourseLookupFailureSpocClient :
      SpocClient(
          username = "24182104",
          sessionManager =
              SessionManager(
                  sessionStore = InMemorySessionStore(),
                  cookieStorageFactory = InMemoryCookieStorageFactory(),
              ),
      ) {
    var courseCalls = 0
    var pagedAssignmentsCalls = 0

    override suspend fun getCurrentTerm(): SpocCurrentTermContent {
      return SpocCurrentTermContent(dqxq = "2026年春季学期", mrxq = "2025-20262")
    }

    override suspend fun getCourses(termCode: String): List<SpocCourseRaw> {
      courseCalls++
      throw SpocException("course lookup failed")
    }

    override suspend fun getAllAssignments(termCode: String): List<SpocPagedAssignmentRaw> {
      pagedAssignmentsCalls++
      return listOf(
          SpocPagedAssignmentRaw(
              zyid = "a1",
              tjzt = "未做",
              zyjzsj = "2026-03-11T15:59:00.000+00:00",
              zymc = "关于Agentic Coding的思考",
              zykssj = "2026-03-03T16:00:00.000+00:00",
              sskcid = "course-1",
              kcmc = "编译原理",
              mf = "满分:0",
          )
      )
    }

    override suspend fun getAssignmentDetail(assignmentId: String): SpocAssignmentDetailRaw {
      throw UnsupportedOperationException("not needed for this test")
    }

    override suspend fun getSubmission(assignmentId: String): SpocSubmissionRaw? {
      throw UnsupportedOperationException("not needed for this test")
    }

    override fun close() = Unit
  }
}
