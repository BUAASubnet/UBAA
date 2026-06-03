package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.DefaultApiFactory
import cn.edu.ubaa.api.feature.CgyyApi
import cn.edu.ubaa.api.local.LocalAuthServiceBackend
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCgyySigner
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.api.local.LocalWebVpnSupport
import cn.edu.ubaa.api.local.localCgyyUpstreamUrl
import cn.edu.ubaa.api.storage.CredentialStore
import com.russhwolf.settings.MapSettings
import io.ktor.client.request.forms.FormDataContent
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.request
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.Parameters
import io.ktor.http.Url
import java.nio.file.Files
import java.nio.file.Path
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlinx.coroutines.test.runTest
import org.junit.Assume.assumeTrue

class LocalCgyyRealIntegrationTest {
  @Test
  fun `real local direct account can read cgyy data`() = runTest {
    assumeTrue(System.getenv("UBAA_REAL_CGYY_TEST") == "true")
    val credentials = loadRealCgyyCredentials()

    prepareMode(ConnectionMode.DIRECT)

    val loginResult =
        LocalAuthServiceBackend().login(credentials.username, credentials.password, null, null)
    assertTrue(loginResult.isSuccess, loginResult.exceptionOrNull()?.message.orEmpty())

    val api = CgyyApi()
    val sites = api.getVenueSites()
    val purposeTypes = api.getPurposeTypes()
    val orders = api.getMyOrders(page = 0, size = 5)

    assertTrue(sites.isSuccess, sites.exceptionOrNull()?.message.orEmpty())
    assertTrue(sites.getOrThrow().isNotEmpty(), "cgyy sites should not be empty")
    assertTrue(purposeTypes.isSuccess, purposeTypes.exceptionOrNull()?.message.orEmpty())
    assertTrue(purposeTypes.getOrThrow().isNotEmpty(), "cgyy purpose types should not be empty")
    assertTrue(orders.isSuccess, orders.exceptionOrNull()?.message.orEmpty())
    println(
        "REAL_DIRECT_CGYY sites=${sites.getOrThrow().size} purposeTypes=${purposeTypes.getOrThrow().size} orders=${orders.getOrThrow().content.size}"
    )
  }

  @Test
  fun `real local webvpn account can read cgyy data`() = runTest {
    assumeTrue(System.getenv("UBAA_REAL_CGYY_TEST") == "true")
    val credentials = loadRealCgyyCredentials()

    prepareMode(ConnectionMode.WEBVPN)

    val loginResult =
        LocalAuthServiceBackend().login(credentials.username, credentials.password, null, null)
    assertTrue(loginResult.isSuccess, loginResult.exceptionOrNull()?.message.orEmpty())

    debugCgyyWebVpnBusinessLogin()

    val api = CgyyApi()
    val sites = api.getVenueSites()
    val purposeTypes = api.getPurposeTypes()
    val orders = api.getMyOrders(page = 0, size = 5)

    assertTrue(sites.isSuccess, sites.exceptionOrNull()?.message.orEmpty())
    assertTrue(sites.getOrThrow().isNotEmpty(), "cgyy sites should not be empty")
    assertTrue(purposeTypes.isSuccess, purposeTypes.exceptionOrNull()?.message.orEmpty())
    assertTrue(purposeTypes.getOrThrow().isNotEmpty(), "cgyy purpose types should not be empty")
    assertTrue(orders.isSuccess, orders.exceptionOrNull()?.message.orEmpty())
    println(
        "REAL_WEBVPN_CGYY sites=${sites.getOrThrow().size} purposeTypes=${purposeTypes.getOrThrow().size} orders=${orders.getOrThrow().content.size}"
    )
  }

  private fun prepareMode(mode: ConnectionMode) {
    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    CredentialStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionRuntime.switchMode(mode)
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    LocalUpstreamClientProvider.reset()
  }

  private suspend fun debugCgyyWebVpnBusinessLogin() {
    val noRedirectClient = LocalUpstreamClientProvider.newNoRedirectClient()
    try {
      var currentUrl =
          localCgyyUpstreamUrl("https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin")
      var step = 0
      while (step < 4) {
        val response = noRedirectClient.get(currentUrl)
        val location = response.headers[HttpHeaders.Location]
        println(
            "REAL_WEBVPN_CGYY manageLoginStep=$step status=${response.status.value} final=${LocalWebVpnSupport.fromWebVpnUrl(response.call.request.url.toString()).substringBefore('?')} location=${location?.let(LocalWebVpnSupport::fromWebVpnUrl)?.substringBefore('?').orEmpty()} setCookieNames=${response.headers.getAll(HttpHeaders.SetCookie).orEmpty().map { it.substringBefore('=') }}"
        )
        if (response.status.value !in 300..399 || location.isNullOrBlank()) {
          val body = response.bodyAsText()
          println(
              "REAL_WEBVPN_CGYY manageLoginTerminal containsMobile=${body.contains("mobileReservation")} containsSsoToken=${body.contains("sso_buaa_zhjs_token")} containsLogin=${body.contains("login", ignoreCase = true)} title=${Regex("<title>(.*?)</title>", RegexOption.IGNORE_CASE).find(body)?.groupValues?.getOrNull(1).orEmpty()}"
          )
          break
        }
        currentUrl = localCgyyUpstreamUrl(LocalWebVpnSupport.fromWebVpnUrl(location))
        step += 1
      }
    } finally {
      noRedirectClient.close()
    }

    val manageLoginResponse =
        LocalUpstreamClientProvider.shared()
            .get(localCgyyUpstreamUrl("https://cgyy.buaa.edu.cn/venue-zhjs-server/sso/manageLogin"))
    val manageLoginBody = manageLoginResponse.bodyAsText()
    val setCookieHeaders = manageLoginResponse.headers.getAll(HttpHeaders.SetCookie).orEmpty()
    println(
        "REAL_WEBVPN_CGYY manageLogin status=${manageLoginResponse.status.value} finalHost=${manageLoginResponse.call.request.url.host} contentType=${manageLoginResponse.headers[HttpHeaders.ContentType].orEmpty()} setCookieNames=${setCookieHeaders.map { it.substringBefore('=') }} bodyPrefix=${manageLoginBody.take(80).replace(Regex("\\s+"), " ")}"
    )

    val storage = LocalCookieStore.storage(ConnectionMode.DIRECT)
    val storedCookies =
        storage.get(Url(localCgyyUpstreamUrl("https://cgyy.buaa.edu.cn/venue-zhjs-server/")))
    println("REAL_WEBVPN_CGYY storedCookies=${storedCookies.map { it.name }}")
    val ssoToken =
        setCookieHeaders.firstNotNullOfOrNull { header ->
          header
              .substringBefore(';')
              .split('=', limit = 2)
              .takeIf { it.size == 2 && it[0].trim() == "sso_buaa_zhjs_token" }
              ?.get(1)
              ?.trim()
              ?.takeIf { it.isNotBlank() }
        }
            ?: storedCookies.firstOrNull { it.name == "sso_buaa_zhjs_token" }?.value
            ?: storedCookies.firstOrNull { it.name == "refresh" }?.value
    println("REAL_WEBVPN_CGYY ssoTokenPresent=${!ssoToken.isNullOrBlank()}")
    if (ssoToken.isNullOrBlank()) return

    val signer = LocalCgyySigner()
    val timestamp = Clock.System.now().toEpochMilliseconds()
    val sign = signer.sign("/api/login", emptyMap(), timestamp)
    val loginResponse =
        LocalUpstreamClientProvider.shared().request(
            localCgyyUpstreamUrl("https://cgyy.buaa.edu.cn/venue-zhjs-server/api/login")
        ) {
          method = HttpMethod.Post
          header(HttpHeaders.Accept, "application/json, text/plain, */*")
          header(
              HttpHeaders.Referrer,
              localCgyyUpstreamUrl("https://cgyy.buaa.edu.cn/venue-zhjs/mobileReservation"),
          )
          header("app-key", signer.appKey)
          header("timestamp", timestamp.toString())
          header("sign", sign)
          header("Sso-Token", ssoToken)
          setBody(FormDataContent(Parameters.Empty))
        }
    val loginBody = loginResponse.bodyAsText()
    println(
        "REAL_WEBVPN_CGYY apiLogin status=${loginResponse.status.value} finalHost=${loginResponse.call.request.url.host} contentType=${loginResponse.headers[HttpHeaders.ContentType].orEmpty()} bodyPrefix=${loginBody.take(160).replace(Regex("\\s+"), " ")}"
    )
  }

  private fun loadRealCgyyCredentials(): RealCgyyCredentials {
    val propertiesPath =
        listOf(Path.of("local.properties"), Path.of("../local.properties"))
            .firstOrNull(Files::exists) ?: Path.of("local.properties")
    assumeTrue(
        "local.properties is required for real local cgyy test",
        Files.exists(propertiesPath),
    )
    val properties = Properties()
    Files.newInputStream(propertiesPath).use(properties::load)
    val username = properties.getProperty("testuser").orEmpty().trim()
    val password = properties.getProperty("testpasswd").orEmpty().trim()
    assumeTrue(
        "testuser/testpasswd are required for real local cgyy test",
        username.isNotBlank() && password.isNotBlank(),
    )
    return RealCgyyCredentials(username, password)
  }

  private data class RealCgyyCredentials(val username: String, val password: String)
}
