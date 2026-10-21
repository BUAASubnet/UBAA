package cn.edu.ubaa.api

import cn.edu.ubaa.api.auth.LoginStatsReporter
import cn.edu.ubaa.api.local.*
import cn.edu.ubaa.api.storage.*
import cn.edu.ubaa.model.dto.JudgeSubmissionStatus
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import java.nio.file.Files
import java.nio.file.Path
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import org.junit.Assume.assumeTrue

/** 显式启用的认证探测；凭据只从本地配置读取，会话仅存在内存，不输出查询参数或响应正文。 */
class LocalJudgeRealIntegrationTest {
  @Test fun realDirectJudge() = verify(ConnectionMode.DIRECT)

  @Test fun realWebVpnJudge() = verify(ConnectionMode.WEBVPN)

  private fun verify(mode: ConnectionMode) {
    assumeTrue(System.getenv("UBAA_REAL_JUDGE_TEST") == "true")
    val selectedMode = System.getenv("UBAA_REAL_JUDGE_MODE")
    assumeTrue(selectedMode.isNullOrBlank() || selectedMode == mode.storageKey)
    val path =
        System.getenv("UBAA_AUTH_ENV_FILE")?.let(Path::of)
            ?: listOf(
                    Path.of(".env.local"),
                    Path.of("../.env.local"),
                    Path.of("local.properties"),
                    Path.of("../local.properties"),
                )
                .firstOrNull(Files::exists)
    requireNotNull(path) { "缺少本地认证测试配置" }
    val properties = Properties().apply { Files.newBufferedReader(path).use(::load) }
    val username =
        (properties.getProperty("UBAA_TEST_USERNAME") ?: properties.getProperty("testuser"))
            .orEmpty()
    val password =
        (properties.getProperty("UBAA_TEST_PASSWORD") ?: properties.getProperty("testpasswd"))
            .orEmpty()
    check(username.isNotBlank() && password.isNotBlank()) { "缺少测试凭据" }
    runBlocking {
      withTimeout(240_000) {
        localConnectionTestMutex.lock()
        try {
          ConnectionModeStore.settings = MapSettings()
          AuthTokensStore.settings = MapSettings()
          ClientIdStore.settings = MapSettings()
          GradeScoreCacheStore.settings = MapSettings()
          CredentialStore.settings = MapSettings()
          LocalAuthSessionStore.settings = MapSettings()
          LocalCookieStore.settings = MapSettings()
          LocalJudgeHistoricalCourseStore.settings = MapSettings()
          ConnectionRuntime.clearSelectedMode()
          ConnectionRuntime.switchMode(mode)
          LoginStatsReporter.reporter = {}
          LocalUpstreamClientProvider.clientFactory = { redirects ->
            client(redirects, LocalCookieStore.storage(mode))
          }
          LocalUpstreamClientProvider.isolatedClientFactory = { redirects, cookies ->
            client(redirects, cookies)
          }
          val result = LocalAuthServiceBackend().login(username, password, null, null)
          assertTrue(
              result.isSuccess,
              "${mode.storageKey} 认证失败：${result.exceptionOrNull()?.let { it::class.simpleName }}",
          )
          assertTrue(username == result.getOrNull()?.user?.schoolid, "登录账户不匹配")
          println("认证探测 mode=${mode.storageKey} UC=成功")
          val backend = LocalJudgeApiBackend()
          val current = backend.getAssignments(false, username)
          println(
              "希冀当前实现 mode=${mode.storageKey} success=${current.isSuccess} count=${current.getOrNull()?.assignments?.size} code=${(current.exceptionOrNull() as? cn.edu.ubaa.api.auth.ApiCallException)?.code}"
          )
          assertTrue(
              current.isSuccess && !current.getOrNull()?.assignments.isNullOrEmpty(),
              "希冀当前实现没有返回作业",
          )
          val initial = current.getOrThrow()
          val now = Clock.System.now().toLocalDateTime(TimeZone.of("Asia/Shanghai"))
          val visibleCount =
              initial.assignments.count { assignment ->
                val due =
                    assignment.dueTime?.let {
                      runCatching { LocalDateTime.parse(it.replace(' ', 'T')) }.getOrNull()
                    }
                assignment.submissionStatus in
                    setOf(JudgeSubmissionStatus.UNSUBMITTED, JudgeSubmissionStatus.PARTIAL) &&
                    (due == null || due >= now)
              }
          println("希冀默认筛选 mode=${mode.storageKey} visible=$visibleCount")
          assertTrue(visibleCount > 0, "测试账号默认筛选后应有当前未完成作业")
          LocalJudgeApiCache.clearAll()
          val refreshed = backend.getAssignments(false, username)
          println(
              "希冀刷新 mode=${mode.storageKey} success=${refreshed.isSuccess} count=${refreshed.getOrNull()?.assignments?.size} historicalCourses=${initial.historicalCutoffCourseIds.size}"
          )
          val groups = initial.assignments.groupBy { it.courseId }
          println("希冀首次各课程数量=" + groups.values.map { it.size })
          println("希冀首次各课程历史过滤=" + groups.keys.map { it in initial.historicalCutoffCourseIds })
          println(
              "希冀刷新各课程数量=" +
                  groups.keys.map { id ->
                    refreshed.getOrNull()?.assignments?.count { it.courseId == id }
                  }
          )
          assertTrue(refreshed.isSuccess, "希冀刷新失败")
          assertTrue(
              initial.assignments.map { it.courseId to it.assignmentId }.toSet() ==
                  refreshed.getOrThrow().assignments.map { it.courseId to it.assignmentId }.toSet(),
              "刷新后作业丢失",
          )
          val first = initial.assignments.first()
          val detail = backend.getAssignmentDetail(first.courseId, first.assignmentId)
          assertTrue(
              detail.isSuccess && detail.getOrNull()?.assignmentId == first.assignmentId,
              "希冀详情读取失败",
          )
          println("希冀详情 mode=${mode.storageKey} success=true")
        } finally {
          LoginStatsReporter.reset()
          ConnectionRuntime.clearSelectedMode()
          localConnectionTestMutex.unlock()
        }
      }
    }
  }

  private fun client(redirects: Boolean, cookies: CookiesStorage) =
      HttpClient(CIO) {
        followRedirects = redirects
        install(HttpCookies) { storage = cookies }
        install(HttpTimeout) {
          requestTimeoutMillis = 20_000
          connectTimeoutMillis = 10_000
          socketTimeoutMillis = 20_000
        }
      }
}
