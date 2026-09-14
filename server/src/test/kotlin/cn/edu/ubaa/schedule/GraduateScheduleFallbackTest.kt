package cn.edu.ubaa.schedule

import cn.edu.ubaa.api.feature.GraduateScheduleLoadException
import cn.edu.ubaa.auth.*
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import kotlin.test.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking

class GraduateScheduleFallbackTest {
  @Test
  fun `门户不可用时直连和 WebVPN 都能访问课表并保留主会话`() = runBlocking {
    for (vpn in listOf(false, true)) {
      Fixture(vpn = vpn).use { fixture ->
        fixture.login()
        assertEquals("20261", fixture.service.fetchTerms(USER).single().itemCode)
        assertEquals(1, fixture.scheduleRequests)
        assertEquals(AcademicPortalType.GRADUATE, fixture.session()?.portalType)
        val probes = fixture.probeRequests
        assertTrue(fixture.service.fetchWeeks(USER, "20261").isEmpty())
        assertTrue(fixture.service.fetchWeeklySchedule(USER, "20261", 1).arrangedList.isEmpty())
        assertEquals(probes, fixture.probeRequests)
        assertNotNull(fixture.session())
      }
    }
  }

  @Test
  fun `门户要求认证时先由可用的课表子应用验证访问权`() =
      runBlocking<Unit> {
        Fixture(undergradStatus = HttpStatusCode.Unauthorized).use { fixture ->
          fixture.login()
          assertEquals("20261", fixture.service.fetchTerms(USER).single().itemCode)
          assertNotNull(fixture.session())
        }
      }

  @Test
  fun `课表自身要求登录时保留认证失败语义`() = runBlocking {
    Fixture(scheduleStatus = HttpStatusCode.Unauthorized).use { fixture ->
      fixture.login()
      assertFailsWith<LoginException> { fixture.service.fetchTerms(USER) }
      assertEquals(AcademicPortalType.UNKNOWN, fixture.session()?.portalType)
    }
  }

  @Test
  fun `课表不可用和取消不能伪装为成功或清除主会话`() =
      runBlocking<Unit> {
        Fixture(scheduleStatus = HttpStatusCode.ServiceUnavailable).use { fixture ->
          fixture.login()
          assertFailsWith<GraduateScheduleLoadException> { fixture.service.fetchTerms(USER) }
          assertNotNull(fixture.session())
          assertEquals(AcademicPortalType.UNKNOWN, fixture.session()?.portalType)
        }
        Fixture(cancelSchedule = true).use { fixture ->
          fixture.login()
          assertFailsWith<CancellationException> { fixture.service.fetchTerms(USER) }
          assertNotNull(fixture.session())
        }
      }

  @Test
  fun `已确认本科门户继续使用本科课表接口`() = runBlocking {
    for (known in listOf(false, true)) {
      Fixture(undergradStatus = HttpStatusCode.OK).use { fixture ->
        fixture.login(if (known) AcademicPortalType.UNDERGRAD else AcademicPortalType.UNKNOWN)
        assertEquals("2026-2027-1", fixture.service.fetchTerms(USER).single().itemCode)
        assertEquals(0, fixture.scheduleRequests)
        assertEquals(AcademicPortalType.UNDERGRAD, fixture.session()?.portalType)
        if (known) assertEquals(0, fixture.probeRequests)
      }
    }
  }

  private class Fixture(
      private val vpn: Boolean = false,
      private val undergradStatus: HttpStatusCode = HttpStatusCode.ServiceUnavailable,
      private val scheduleStatus: HttpStatusCode = HttpStatusCode.OK,
      private val cancelSchedule: Boolean = false,
  ) : AutoCloseable {
    private val originalVpn = VpnCipher.isEnabled.also { VpnCipher.isEnabled = vpn }
    var scheduleRequests = 0
    var probeRequests = 0
    private val manager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { client() },
        )
    private val warmup = AcademicPortalWarmupCoordinator(sessionManager = manager)
    val service = ScheduleService(sessionManager = manager, portalWarmupCoordinator = warmup)

    suspend fun login(type: AcademicPortalType = AcademicPortalType.UNKNOWN) {
      manager.commitSession(manager.prepareSession(USER), UserData("示例学生", USER), type)
    }

    suspend fun session() = manager.getSession(USER, SessionManager.SessionAccess.READ_ONLY)

    private fun client() =
        HttpClient(
            MockEngine { request ->
              when {
                request.url.encodedPath.endsWith("/currentUser.do") -> {
                  probeRequests++
                  respond("""{"code":"0","data":{}}""", undergradStatus)
                }
                request.url.encodedPath.endsWith("/getUserInfo.do") -> {
                  probeRequests++
                  respond("", HttpStatusCode.Forbidden)
                }
                request.url.encodedPath.endsWith("/schoolCalendars.do") ->
                    respond(
                        """{"code":"0","msg":null,"datas":[{"itemCode":"2026-2027-1","itemName":"本科示例学期","selected":true,"itemIndex":0}]}"""
                    )
                request.url.encodedPath.endsWith("/kfdxnxqcx.do") ->
                    respond(
                        """{"code":"0","datas":{"kfdxnxqcx":{"totalSize":1,"rows":[{"XNXQDM":"20261","XNXQDM_DISPLAY":"示例学期"}]}}}"""
                    )
                request.url.encodedPath.endsWith("/bykb/loadXskbData.do") -> {
                  assertEquals(if (vpn) "d.buaa.edu.cn" else "gsmis.buaa.edu.cn", request.url.host)
                  assertEquals(HttpMethod.Post, request.method)
                  scheduleRequests++
                  if (cancelSchedule) throw CancellationException("模拟取消")
                  respond("""{"code":1,"jgList":[],"rwList":[],"jcfaList":[]}""", scheduleStatus)
                }
                request.url.encodedPath.endsWith("/*default/index.do") ->
                    respond("<html>已登录</html>")
                else -> error("未预期的请求路径：${request.url.encodedPath}")
              }
            }
        )

    override fun close() {
      warmup.close()
      manager.close()
      VpnCipher.isEnabled = originalVpn
    }
  }

  private companion object {
    const val USER = "schedule-test-student"
  }
}
