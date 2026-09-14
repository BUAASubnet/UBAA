package cn.edu.ubaa.api

import cn.edu.ubaa.api.auth.LoginStatsReporter
import cn.edu.ubaa.api.core.DefaultApiFactory
import cn.edu.ubaa.api.core.getDefaultEngine
import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.api.local.*
import cn.edu.ubaa.api.storage.*
import cn.edu.ubaa.repository.ScheduleRepository
import cn.edu.ubaa.repository.ScheduleStore
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.serialization.kotlinx.json.json
import java.nio.file.Files
import java.nio.file.Path
import java.util.Properties
import kotlin.test.*
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import org.junit.Assume.assumeTrue

/** 显式启用后读取 local.properties；只查询学校课表，所有测试缓存均存于内存。 */
class LocalScheduleRealIntegrationTest {
  @Test fun realDirectSchedule() = verify(ConnectionMode.DIRECT)

  @Test fun realWebVpnSchedule() = verify(ConnectionMode.WEBVPN)

  private fun verify(mode: ConnectionMode) {
    assumeTrue(System.getenv("UBAA_REAL_SCHEDULE_TEST") == "true")
    val requestedMode = System.getenv("UBAA_REAL_SCHEDULE_MODE")
    assumeTrue(requestedMode.isNullOrBlank() || requestedMode == mode.storageKey)
    val path =
        listOf(Path.of("local.properties"), Path.of("../local.properties"))
            .firstOrNull(Files::exists)
    requireNotNull(path) { "local.properties is required" }
    val properties = Properties().apply { Files.newInputStream(path).use(::load) }
    val username = properties.getProperty("testuser").orEmpty().trim()
    val password = properties.getProperty("testpasswd").orEmpty()
    check(username.isNotBlank() && password.isNotBlank()) { "test credentials are required" }

    runBlocking {
      withTimeout(300_000) {
        localConnectionTestMutex.lock()
        try {
          ConnectionModeStore.settings = MapSettings()
          AuthTokensStore.settings = MapSettings()
          ClientIdStore.settings = MapSettings()
          GradeScoreCacheStore.settings = MapSettings()
          LocalAuthSessionStore.settings = MapSettings()
          LocalCookieStore.settings = MapSettings()
          CredentialStore.settings = MapSettings()
          ScheduleStore.settings = MapSettings()
          ConnectionRuntime.clearSelectedMode()
          ConnectionRuntime.switchMode(mode)
          ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
          LoginStatsReporter.reporter = {}
          // 不安装 HTTP Logging，避免 SSO 重定向 URL 中的 ticket 进入测试报告。
          LocalUpstreamClientProvider.clientFactory = { redirects ->
            client(redirects, LocalCookieStore.storage(mode))
          }
          LocalUpstreamClientProvider.isolatedClientFactory = { redirects, cookies ->
            client(redirects, cookies)
          }
          LocalAuthServiceBackend().login(username, password, null, null).checked("login")
          ScheduleStore.useAccount(username)
          val repo = ScheduleRepository(ScheduleApi())
          assertFalse(ScheduleStore.hasSavedSchedule())
          val today = repo.loadTodayClasses().checked("online today")
          val terms = repo.loadTerms().checked("online terms")
          val term = terms.firstOrNull { it.selected } ?: terms.first()
          val weeks = repo.loadWeeks(term.itemCode).checked("online weeks")
          assertEquals(
              weeks.size,
              weeks.distinctBy { it.serialNumber }.size,
              "duplicate upstream weeks",
          )
          val week = weeks.firstOrNull { it.curWeek } ?: weeks.firstOrNull()
          val weekly =
              week?.let { repo.loadWeekly(term.itemCode, it.serialNumber).checked("online week") }
          assertFalse(ScheduleStore.hasSavedSchedule(), "online browsing must not localize")
          println(
              "REAL_SCHEDULE mode=${mode.storageKey} online=true terms=${terms.size} weeks=${weeks.size} todayClasses=${today.size} weeklyCodeIsAccount=${weekly?.code == username} weeklyCodeMatchesTerm=${weekly?.code == term.itemCode}"
          )
          weeks.take(2).forEach {
            val start =
                it.startDate.takeIf { value -> Regex("[0-9T:/ .+Z-]{1,40}").matches(value) }
                    ?: "other-format"
            val end =
                it.endDate.takeIf { value -> Regex("[0-9T:/ .+Z-]{1,40}").matches(value) }
                    ?: "other-format"
            println(
                "REAL_SCHEDULE week=${it.serialNumber} startDate=$start endDate=$end termMatches=${it.term == term.itemCode}"
            )
          }
          val snapshot = repo.update(term.itemCode).checked("localize semester")
          assertEquals(weeks.map { it.serialNumber }.toSet(), snapshot.schedules.keys)
          assertTrue(ScheduleStore.hasSavedSchedule())
          val restored = ScheduleRepository()
          assertEquals(
              snapshot.schedules,
              restored.schedules(term.itemCode).checked("restored schedules"),
          )
          assertTrue(restored.loadTodayClasses(offlineOnly = true).isSuccess)
          println(
              "REAL_SCHEDULE mode=${mode.storageKey} localized=true restored=true savedWeeks=${snapshot.schedules.size} codeMismatches=${snapshot.schedules.values.count { it.code != term.itemCode }}"
          )
        } finally {
          LoginStatsReporter.reset()
          ConnectionRuntime.clearSelectedMode()
          ScheduleStore.settings = MapSettings()
          localConnectionTestMutex.unlock()
        }
      }
    }
  }

  private fun <T> Result<T>.checked(stage: String): T {
    assertTrue(isSuccess, "$stage failed (${exceptionOrNull()?.let { it::class.simpleName }})")
    return getOrThrow()
  }

  private fun client(redirects: Boolean, cookies: CookiesStorage) =
      HttpClient(getDefaultEngine()) {
        followRedirects = redirects
        install(ContentNegotiation) {
          json(
              Json {
                ignoreUnknownKeys = true
                isLenient = true
              }
          )
        }
        install(HttpCookies) { storage = cookies }
        install(HttpTimeout) {
          requestTimeoutMillis = 30_000
          connectTimeoutMillis = 10_000
          socketTimeoutMillis = 30_000
        }
      }
}
