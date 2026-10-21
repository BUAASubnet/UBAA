package cn.edu.ubaa.api

import cn.edu.ubaa.api.auth.LoginStatsReporter
import cn.edu.ubaa.api.local.*
import cn.edu.ubaa.api.storage.*
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.HttpResponseValidator
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.plugins.cookies.HttpCookies
import java.nio.file.Files
import java.nio.file.Path
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assume.assumeTrue

/** 显式启用的认证探测；凭据只从本地配置读取，会话仅存在内存，不输出查询参数或响应正文。 */
class LocalAuthRealIntegrationTest {
  @Test fun realDirectAuth() = verify(ConnectionMode.DIRECT)

  @Test fun realWebVpnAuth() = verify(ConnectionMode.WEBVPN)

  private fun verify(mode: ConnectionMode) {
    assumeTrue(System.getenv("UBAA_REAL_AUTH_TEST") == "true")
    val selectedMode = System.getenv("UBAA_REAL_AUTH_MODE")
    assumeTrue(selectedMode.isNullOrBlank() || selectedMode == mode.storageKey)
    val path =
        System.getenv("UBAA_AUTH_ENV_FILE")?.let(Path::of)
            ?: listOf(Path.of(".env.local"), Path.of("../.env.local")).firstOrNull(Files::exists)
    requireNotNull(path) { "缺少本地认证测试配置" }
    val properties = Properties().apply { Files.newBufferedReader(path).use(::load) }
    val username = properties.getProperty("UBAA_TEST_USERNAME").orEmpty()
    val password = properties.getProperty("UBAA_TEST_PASSWORD").orEmpty()
    check(username.isNotBlank() && password.isNotBlank()) { "缺少测试凭据" }
    runBlocking {
      withTimeout(120_000) {
        localConnectionTestMutex.lock()
        try {
          ConnectionModeStore.settings = MapSettings()
          AuthTokensStore.settings = MapSettings()
          ClientIdStore.settings = MapSettings()
          GradeScoreCacheStore.settings = MapSettings()
          CredentialStore.settings = MapSettings()
          LocalAuthSessionStore.settings = MapSettings()
          LocalCookieStore.settings = MapSettings()
          ConnectionRuntime.clearSelectedMode()
          ConnectionRuntime.switchMode(mode)
          LoginStatsReporter.reporter = {}
          LocalUpstreamClientProvider.clientFactory = { redirects ->
            client(redirects, LocalCookieStore.storage(mode), mode)
          }
          LocalUpstreamClientProvider.isolatedClientFactory = { redirects, cookies ->
            client(redirects, cookies, ConnectionMode.DIRECT)
          }
          val result = LocalAuthServiceBackend().login(username, password, null, null)
          assertTrue(
              result.isSuccess,
              "${mode.storageKey} 认证失败：${result.exceptionOrNull()?.let { it::class.simpleName }}",
          )
          assertTrue(username == result.getOrNull()?.user?.schoolid, "登录账户不匹配")
          println("认证探测 mode=${mode.storageKey} UC=成功")
          val portal = probeLocalUndergradPortal()
          println("认证探测 mode=${mode.storageKey} BYXT=$portal")
          assertEquals(LocalUndergradPortalProbeResult.UNDERGRAD_READY, portal)
        } finally {
          LoginStatsReporter.reset()
          ConnectionRuntime.clearSelectedMode()
          localConnectionTestMutex.unlock()
        }
      }
    }
  }

  private fun client(redirects: Boolean, cookies: CookiesStorage, mode: ConnectionMode) =
      HttpClient(CIO) {
        followRedirects = redirects
        install(HttpCookies) { storage = cookies }
        install(HttpTimeout) {
          requestTimeoutMillis = 20_000
          connectTimeoutMillis = 10_000
          socketTimeoutMillis = 20_000
        }
        HttpResponseValidator {
          validateResponse { response ->
            val url = response.call.request.url
            println(
                "认证探测 mode=${mode.storageKey} host=${url.host} path=${url.encodedPath} HTTP=${response.status.value}"
            )
          }
        }
      }
}
