package cn.edu.ubaa.auth

import cn.edu.ubaa.exam.ExamService
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.schedule.ScheduleService
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlinx.coroutines.runBlocking

class AcademicPortalSupportTest {

  @Test
  fun classifyUndergradPortalResponse() {
    val result =
        ByxtService.classifyUndergradResponse(
            status = HttpStatusCode.OK,
            finalUrl = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do",
            body = """{"code":"0","data":{"name":"Alice"}}""",
        )

    assertEquals(AcademicPortalProbeResult.UNDERGRAD_READY, result)
  }

  @Test
  fun classifyGraduatePortalResponse() {
    val result =
        ByxtService.classifyGraduateResponse(
            status = HttpStatusCode.OK,
            finalUrl =
                "https://gsmis.buaa.edu.cn/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do",
            body = """{"code":"0","data":{"userId":"SY2511503"}}""",
        )

    assertEquals(AcademicPortalProbeResult.GRADUATE_READY, result)
  }

  @Test
  fun classifySsoRedirectAsUnauthenticated() {
    val result =
        ByxtService.classifyUndergradResponse(
            status = HttpStatusCode.Found,
            finalUrl = "https://sso.buaa.edu.cn/login?service=...",
            body = "",
        )

    assertEquals(AcademicPortalProbeResult.SSO_REQUIRED, result)
  }

  @Test
  fun classifyUnknownHtmlAsUnavailable() {
    val result =
        ByxtService.classifyGraduateResponse(
            status = HttpStatusCode.OK,
            finalUrl = "https://gsmis.buaa.edu.cn/gsapp/sys/yjsemaphome/portal/index.do",
            body = "<html><body>unexpected</body></html>",
        )

    assertEquals(AcademicPortalProbeResult.UNAVAILABLE, result)
  }

  @Test
  fun graduateScheduleRequestDoesNotInvalidateSession() = runBlocking {
    val sessionManager = createSessionManager()
    val scheduleService = ScheduleService(sessionManager = sessionManager)

    val candidate = sessionManager.prepareSession("graduate-user")
    sessionManager.commitSession(
        candidate,
        UserData("Graduate User", "SY2511503"),
        AcademicPortalType.GRADUATE,
    )

    val error =
        assertFailsWith<UnsupportedAcademicPortalException> {
          scheduleService.fetchTerms("graduate-user")
        }

    assertEquals("研究生账号暂不支持当前本科教务接口", error.message)
    assertNotNull(sessionManager.getSession("graduate-user", SessionManager.SessionAccess.READ_ONLY))
    Unit
  }

  @Test
  fun graduateExamRequestDoesNotInvalidateSession() = runBlocking {
    val sessionManager = createSessionManager()
    val examService = ExamService(sessionManager = sessionManager)

    val candidate = sessionManager.prepareSession("graduate-user")
    sessionManager.commitSession(
        candidate,
        UserData("Graduate User", "SY2511503"),
        AcademicPortalType.GRADUATE,
    )

    val error =
        assertFailsWith<UnsupportedAcademicPortalException> {
          examService.getExamArrangement("graduate-user", "20252")
        }

    assertEquals("研究生账号暂不支持当前本科考试接口", error.message)
    assertNotNull(sessionManager.getSession("graduate-user", SessionManager.SessionAccess.READ_ONLY))
    Unit
  }

  @Test
  fun unknownPortalGraduateRequestIsReclassifiedWithoutInvalidation() = runBlocking {
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage -> graduateAwareMockClient() },
        )
    val scheduleService = ScheduleService(sessionManager = sessionManager)

    val candidate = sessionManager.prepareSession("graduate-user")
    sessionManager.commitSession(candidate, UserData("Graduate User", "SY2511503"))

    assertFailsWith<UnsupportedAcademicPortalException> {
      scheduleService.fetchTerms("graduate-user")
    }

    val session = sessionManager.getSession("graduate-user", SessionManager.SessionAccess.READ_ONLY)
    assertNotNull(session)
    assertEquals(AcademicPortalType.GRADUATE, session.portalType)
  }

  private fun createSessionManager(): SessionManager {
    return SessionManager(
        sessionStore = InMemorySessionStore(),
        cookieStorageFactory = InMemoryCookieStorageFactory(),
        clientFactory = { _: CookiesStorage -> emptyMockClient() },
    )
  }

  private fun emptyMockClient(): HttpClient {
    return HttpClient(MockEngine) {
      engine {
        addHandler {
          respond(
              content = "",
              status = HttpStatusCode.OK,
              headers = jsonHeaders(),
          )
        }
      }
    }
  }

  private fun graduateAwareMockClient(): HttpClient {
    return HttpClient(MockEngine) {
      engine {
        addHandler { request ->
          when {
            request.url.encodedPath.endsWith("/jwapp/sys/homeapp/api/home/currentUser.do") ->
                respond(
                    content = "",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
            request.url.encodedPath.endsWith(
                "/gsapp/sys/yjsemaphome/modules/pubWork/getUserInfo.do"
            ) ->
                respond(
                    content = """{"code":"0","data":{"userId":"SY2511503"}}""",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
            else ->
                respond(
                    content = "",
                    status = HttpStatusCode.OK,
                    headers = jsonHeaders(),
                )
          }
        }
      }
    }
  }

  private fun jsonHeaders() = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString())
}
