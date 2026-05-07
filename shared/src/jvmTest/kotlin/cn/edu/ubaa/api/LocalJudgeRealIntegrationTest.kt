package cn.edu.ubaa.api

import cn.edu.ubaa.api.feature.JudgeApi
import cn.edu.ubaa.api.local.LocalAuthServiceBackend
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalJudgeApiCache
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.api.local.localUpstreamUrl
import cn.edu.ubaa.api.storage.CredentialStore
import cn.edu.ubaa.model.dto.JudgeAssignmentDetailKeyDto
import com.russhwolf.settings.MapSettings
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import java.nio.file.Files
import java.nio.file.Path
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest
import org.junit.Assume.assumeTrue

class LocalJudgeRealIntegrationTest {
  @Test
  fun `real local direct account can fetch judge assignments`() = runTest {
    assumeTrue(System.getenv("UBAA_REAL_JUDGE_TEST") == "true")
    val credentials = loadRealJudgeCredentials()

    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    CredentialStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionRuntime.switchMode(ConnectionMode.DIRECT)
    LocalJudgeApiCache.clearAll()

    val loginResult =
        LocalAuthServiceBackend().login(credentials.username, credentials.password, null, null)
    assertTrue(loginResult.isSuccess, loginResult.exceptionOrNull()?.message.orEmpty())

    val rawAssignments = fetchRawAssignmentCountLikePython()
    println("REAL_LOCAL_JUDGE raw_assignments=$rawAssignments")

    val api = JudgeApi()
    val assignmentsResult = api.getAssignments()
    assertTrue(assignmentsResult.isSuccess, assignmentsResult.exceptionOrNull()?.message.orEmpty())
    val assignments = assignmentsResult.getOrThrow().assignments
    println("REAL_LOCAL_JUDGE assignments=${assignments.size}")
    assertTrue(
        assignments.isNotEmpty(),
        "real local account should expose current judge assignments",
    )

    val allAssignmentsResult = api.getAssignments(includeExpired = true)
    assertTrue(
        allAssignmentsResult.isSuccess,
        allAssignmentsResult.exceptionOrNull()?.message.orEmpty(),
    )
    val allAssignments = allAssignmentsResult.getOrThrow().assignments
    println("REAL_LOCAL_JUDGE include_expired_assignments=${allAssignments.size}")
    assertTrue(
        allAssignments.isNotEmpty(),
        "real local account should expose judge assignments when expired assignments are included",
    )

    val first = allAssignments.first()
    val detailsResult =
        api.getAssignmentDetails(
            listOf(JudgeAssignmentDetailKeyDto(first.courseId, first.assignmentId))
        )
    assertTrue(detailsResult.isSuccess, detailsResult.exceptionOrNull()?.message.orEmpty())
    println("REAL_LOCAL_JUDGE details=${detailsResult.getOrThrow().details.size}")
  }

  private suspend fun fetchRawAssignmentCountLikePython(): Int {
    val client = LocalUpstreamClientProvider.shared()
    val activationResponse =
        client.get(localUpstreamUrl(JUDGE_SERVICE_LOGIN_URL)) { applyJudgeHeaders() }
    activationResponse.headers[HttpHeaders.Location]
        ?.takeIf { it.isNotBlank() }
        ?.let { location ->
          client.get(localUpstreamUrl(location)) { applyJudgeHeaders() }.bodyAsText()
        }
    val coursesResponse =
        client.get(localUpstreamUrl("https://judge.buaa.edu.cn/courselist.jsp?courseID=0")) {
          applyJudgeHeaders()
        }
    val coursesHtml = coursesResponse.bodyAsText()
    val courses =
        Regex("""courselist\.jsp\?courseID=(\d+)""")
            .findAll(coursesHtml)
            .map { it.groupValues[1] }
            .filter { it != "0" }
            .distinct()
            .toList()
    println("REAL_LOCAL_JUDGE raw_courses=${courses.size}")
    return courses.sumOf { courseId ->
      client
          .get(localUpstreamUrl("https://judge.buaa.edu.cn/courselist.jsp?courseID=$courseId")) {
            applyJudgeHeaders()
          }
          .bodyAsText()
      val assignmentsHtml =
          client
              .get(localUpstreamUrl("https://judge.buaa.edu.cn/assignment/index.jsp")) {
                applyJudgeHeaders()
              }
              .bodyAsText()
      Regex("""assignID=(\d+)""")
          .findAll(assignmentsHtml)
          .map { it.groupValues[1] }
          .distinct()
          .count()
    }
  }

  private fun io.ktor.client.request.HttpRequestBuilder.applyJudgeHeaders() {
    header(HttpHeaders.Accept, JUDGE_ACCEPT_HEADER)
    header(HttpHeaders.AcceptLanguage, "zh-CN,zh;q=0.9")
    header(HttpHeaders.UserAgent, JUDGE_USER_AGENT)
  }

  private fun loadRealJudgeCredentials(): RealJudgeCredentials {
    val propertiesPath =
        listOf(Path.of("local.properties"), Path.of("../local.properties"))
            .firstOrNull(Files::exists) ?: Path.of("local.properties")
    assumeTrue(
        "local.properties is required for real local judge test",
        Files.exists(propertiesPath),
    )
    val properties = Properties()
    Files.newInputStream(propertiesPath).use(properties::load)
    val username = properties.getProperty("testuser").orEmpty().trim()
    val password = properties.getProperty("testpasswd").orEmpty().trim()
    assumeTrue(
        "testuser/testpasswd are required for real local judge test",
        username.isNotBlank() && password.isNotBlank(),
    )
    return RealJudgeCredentials(username, password)
  }

  private data class RealJudgeCredentials(val username: String, val password: String)

  private companion object {
    private const val JUDGE_SERVICE_LOGIN_URL =
        "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F"
    private const val JUDGE_ACCEPT_HEADER =
        "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
    private const val JUDGE_USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3"
  }
}
