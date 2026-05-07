package cn.edu.ubaa.judge

import cn.edu.ubaa.auth.AcademicPortalProbeResult
import cn.edu.ubaa.auth.AcademicPortalWarmupCoordinator
import cn.edu.ubaa.auth.AuthService
import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemoryRefreshTokenStore
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.RefreshTokenService
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.LoginRequest
import cn.edu.ubaa.utils.VpnCipher
import java.nio.file.Files
import java.nio.file.Path
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import org.junit.Assume.assumeTrue

class JudgeRealIntegrationTest {
  @Test
  fun `real test account can fetch judge assignments and detail`() = runBlocking {
    assumeTrue(System.getenv("UBAA_REAL_JUDGE_TEST") == "true")
    val credentials = loadRealJudgeCredentials()
    val originalVpnEnabled = VpnCipher.isEnabled
    VpnCipher.isEnabled = false
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
        )
    val warmupCoordinator =
        AcademicPortalWarmupCoordinator(
            sessionManager = sessionManager,
            portalProbe = { AcademicPortalProbeResult.UNAVAILABLE },
        )
    val authService =
        AuthService(
            sessionManager = sessionManager,
            refreshTokenService =
                RefreshTokenService(refreshTokenStore = InMemoryRefreshTokenStore()),
            portalWarmupCoordinator = warmupCoordinator,
        )

    try {
      authService.login(
          LoginRequest(username = credentials.username, password = credentials.password)
      )

      val service = JudgeService(clientProvider = { JudgeClient(it, sessionManager) })
      val assignments = service.getAssignments(credentials.username).assignments
      println("REAL_JUDGE assignments=${assignments.size}")
      assertTrue(assignments.isNotEmpty(), "real account should expose judge assignments")

      val first = assignments.first()
      val detail =
          service.getAssignmentDetail(
              username = credentials.username,
              courseId = first.courseId,
              assignmentId = first.assignmentId,
          )
      println(
          "REAL_JUDGE first_detail total=${detail.totalProblems} problems=${detail.problems.size}"
      )
      assertTrue(detail.title.isNotBlank(), "real judge detail should include a title")
    } finally {
      serviceCleanup(sessionManager, warmupCoordinator)
      VpnCipher.isEnabled = originalVpnEnabled
    }
  }

  private fun loadRealJudgeCredentials(): RealJudgeCredentials {
    val propertiesPath =
        listOf(Path.of("local.properties"), Path.of("../local.properties"))
            .firstOrNull(Files::exists) ?: Path.of("local.properties")
    assumeTrue("local.properties is required for real judge test", Files.exists(propertiesPath))
    val properties = Properties()
    Files.newInputStream(propertiesPath).use(properties::load)
    val username = properties.getProperty("testuser").orEmpty().trim()
    val password = properties.getProperty("testpasswd").orEmpty().trim()
    assumeTrue(
        "testuser/testpasswd are required for real judge test",
        username.isNotBlank() && password.isNotBlank(),
    )
    return RealJudgeCredentials(username, password)
  }

  private fun serviceCleanup(
      sessionManager: SessionManager,
      warmupCoordinator: AcademicPortalWarmupCoordinator,
  ) {
    warmupCoordinator.close()
    sessionManager.close()
  }

  private data class RealJudgeCredentials(val username: String, val password: String)
}
