package cn.edu.ubaa.api

import cn.edu.ubaa.api.core.DefaultApiFactory
import cn.edu.ubaa.api.feature.SigninApi
import cn.edu.ubaa.api.local.LocalAuthServiceBackend
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.api.local.LocalWebVpnSupport
import cn.edu.ubaa.api.local.localUpstreamUrl
import cn.edu.ubaa.api.storage.CredentialStore
import com.russhwolf.settings.MapSettings
import io.ktor.client.request.get
import io.ktor.client.request.parameter
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.Url
import java.nio.file.Files
import java.nio.file.Path
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assume.assumeTrue

class LocalSigninRealIntegrationTest {
  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun `real local direct account can resolve iclass loginName and app login`() = runTest {
    assumeTrue(System.getenv("UBAA_REAL_SIGNIN_TEST") == "true")
    val credentials = loadRealSigninCredentials()

    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    CredentialStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionRuntime.switchMode(ConnectionMode.DIRECT)
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    LocalUpstreamClientProvider.reset()

    val loginResult =
        LocalAuthServiceBackend().login(credentials.username, credentials.password, null, null)
    assertTrue(loginResult.isSuccess, loginResult.exceptionOrNull()?.message.orEmpty())

    val loginName = resolveRealIclassLoginName()
    println("REAL_LOCAL_SIGNIN loginNameLength=${loginName.length}")

    val appLoginPayload = performIclassAppLogin(loginName)
    val statusVal = appLoginPayload["STATUS"]?.jsonPrimitive
    val statusStr = statusVal?.contentOrNull ?: statusVal?.intOrNull?.toString()
    assertTrue(
        statusStr == "0" || statusStr == "200" || statusStr == "success",
        "STATUS should be success but was: $statusStr",
    )
    val result = appLoginPayload["result"]?.jsonObject
    val userId = result?.get("id")?.jsonPrimitive?.content.orEmpty()
    val sessionId = result?.get("sessionId")?.jsonPrimitive?.content.orEmpty()
    assertTrue(userId.isNotBlank(), "iclass app login should return user id")
    assertTrue(sessionId.isNotBlank(), "iclass app login should return sessionId")
    println(
        "REAL_LOCAL_SIGNIN appLoginUserIdLength=${userId.length} sessionIdLength=${sessionId.length}"
    )

    val classesResult = SigninApi().getTodayClasses()
    assertTrue(classesResult.isSuccess, classesResult.exceptionOrNull()?.message.orEmpty())
    println("REAL_LOCAL_SIGNIN todayClasses=${classesResult.getOrThrow().data.size}")
  }

  @Test
  fun `real local webvpn account can resolve iclass loginName and app login`() = runTest {
    assumeTrue(System.getenv("UBAA_REAL_SIGNIN_TEST") == "true")
    val credentials = loadRealSigninCredentials()

    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    CredentialStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionRuntime.switchMode(ConnectionMode.WEBVPN)
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    LocalUpstreamClientProvider.reset()

    val loginResult =
        LocalAuthServiceBackend().login(credentials.username, credentials.password, null, null)
    assertTrue(loginResult.isSuccess, loginResult.exceptionOrNull()?.message.orEmpty())

    val loginName = resolveRealIclassLoginName()
    println("REAL_WEBVPN_SIGNIN loginNameLength=${loginName.length}")

    val appLoginPayload = performIclassAppLogin(loginName)
    val statusVal = appLoginPayload["STATUS"]?.jsonPrimitive
    val statusStr = statusVal?.contentOrNull ?: statusVal?.intOrNull?.toString()
    assertTrue(
        statusStr == "0" || statusStr == "200" || statusStr == "success",
        "STATUS should be success but was: $statusStr",
    )
    val result = appLoginPayload["result"]?.jsonObject
    val userId = result?.get("id")?.jsonPrimitive?.content.orEmpty()
    val sessionId = result?.get("sessionId")?.jsonPrimitive?.content.orEmpty()
    assertTrue(userId.isNotBlank(), "iclass app login should return user id")
    assertTrue(sessionId.isNotBlank(), "iclass app login should return sessionId")
    println(
        "REAL_WEBVPN_SIGNIN appLoginUserIdLength=${userId.length} sessionIdLength=${sessionId.length}"
    )

    // Test SigninApi which creates its own internal session via resolveLoginName
    val classesResult = SigninApi().getTodayClasses()
    assertTrue(classesResult.isSuccess, classesResult.exceptionOrNull()?.message.orEmpty())
    println("REAL_WEBVPN_SIGNIN todayClasses=${classesResult.getOrThrow().data.size}")
    assertTrue(
        classesResult.getOrThrow().data.isNotEmpty(),
        "WEBVPN mode should return at least one class",
    )
  }

  private suspend fun resolveRealIclassLoginName(): String {
    val client = LocalUpstreamClientProvider.newNoRedirectClient()
    try {
      var currentUrl = localUpstreamUrl("https://iclass.buaa.edu.cn:8346/?type=jumpMyCenter")
      repeat(8) { step ->
        val response = client.get(currentUrl)
        val finalUrl = LocalWebVpnSupport.fromWebVpnUrl(response.call.request.url.toString())
        val location =
            response.headers[HttpHeaders.Location]?.let(LocalWebVpnSupport::fromWebVpnUrl)
        println(
            "REAL_LOCAL_SIGNIN jumpStep=$step status=${response.status.value} finalHost=${hostOf(finalUrl)} locationHost=${location?.let(::hostOf).orEmpty()} finalHasLoginName=${extractSigninLoginNameFromUrl(finalUrl) != null} locationHasLoginName=${location?.let(::extractSigninLoginNameFromUrl) != null}"
        )
        extractSigninLoginNameFromUrl(finalUrl)?.let {
          return it
        }
        location?.let {
          extractSigninLoginNameFromUrl(it)?.let { loginName ->
            return loginName
          }
        }
        if (response.status.value !in 300..399 || location.isNullOrBlank()) {
          val body = response.bodyAsText()
          println(
              "REAL_LOCAL_SIGNIN terminalBodyLength=${body.length} bodyHasLoginName=${body.contains("loginName", ignoreCase = true)} bodyHasSso=${body.contains("sso.buaa.edu.cn", ignoreCase = true)}"
          )
          extractSigninLoginNameFromUrl(body)?.let {
            return it
          }
          error("iclass MyCenter jump did not expose loginName")
        }
        currentUrl = resolveRedirectUrl(response.call.request.url, location)
      }
      error("iclass MyCenter jump exceeded redirect limit")
    } finally {
      client.close()
    }
  }

  private fun resolveRedirectUrl(currentUrl: Url, location: String): String {
    if (location.startsWith("http://") || location.startsWith("https://")) {
      return localUpstreamUrl(location)
    }
    val scheme = currentUrl.protocol.name
    val authority = buildString {
      append(scheme)
      append("://")
      append(currentUrl.host)
      if (currentUrl.specifiedPort > 0) {
        append(':')
        append(currentUrl.specifiedPort)
      }
    }
    return when {
      location.startsWith("/") -> "$authority$location"
      else -> "$authority/${location}"
    }
  }

  private fun hostOf(url: String): String =
      runCatching { Url(url).host }.getOrElse { "unparseable" }

  private suspend fun performIclassAppLogin(loginName: String) =
      json
          .parseToJsonElement(
              LocalUpstreamClientProvider.shared()
                  .get(localUpstreamUrl("https://iclass.buaa.edu.cn:8347/app/user/login.action")) {
                    parameter("password", "")
                    parameter("phone", loginName)
                    parameter("userLevel", "1")
                    parameter("verificationType", "2")
                    parameter("verificationUrl", "")
                  }
                  .bodyAsText()
          )
          .jsonObject

  private fun loadRealSigninCredentials(): RealSigninCredentials {
    val propertiesPath =
        listOf(Path.of("local.properties"), Path.of("../local.properties"))
            .firstOrNull(Files::exists) ?: Path.of("local.properties")
    assumeTrue(
        "local.properties is required for real local signin test",
        Files.exists(propertiesPath),
    )
    val properties = Properties()
    Files.newInputStream(propertiesPath).use(properties::load)
    val username = properties.getProperty("testuser").orEmpty().trim()
    val password = properties.getProperty("testpasswd").orEmpty().trim()
    assumeTrue(
        "testuser/testpasswd are required for real local signin test",
        username.isNotBlank() && password.isNotBlank(),
    )
    return RealSigninCredentials(username, password)
  }

  private data class RealSigninCredentials(val username: String, val password: String)

  private fun currentSigninDate(): String {
    val date = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
    return buildString {
      append(date.year)
      append(date.month.ordinal.plus(1).toString().padStart(2, '0'))
      append(date.day.toString().padStart(2, '0'))
    }
  }
}
