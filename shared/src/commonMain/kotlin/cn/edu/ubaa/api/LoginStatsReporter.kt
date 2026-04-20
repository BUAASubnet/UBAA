package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.LoginStatsConnectionMode
import cn.edu.ubaa.model.dto.LoginStatsReportRequest
import cn.edu.ubaa.model.dto.LoginStatsSuccessMode
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType

internal object LoginStatsReporter {
  internal var reporter: suspend (LoginStatsReportRequest) -> Unit = defaultReporter()

  suspend fun reportSuccess(
      username: String,
      successMode: LoginStatsSuccessMode,
      connectionMode: ConnectionMode,
  ) {
    if (username.isBlank()) {
      return
    }
    val request =
        LoginStatsReportRequest(
            username = username,
            successMode = successMode,
            connectionMode = connectionMode.toLoginStatsConnectionMode(),
        )
    try {
      reporter(request)
    } catch (_: Exception) {}
  }

  fun reset() {
    reporter = defaultReporter()
  }

  private fun defaultReporter(): suspend (LoginStatsReportRequest) -> Unit = { request ->
    ApiClientProvider.shared.getClient().post("api/v1/auth/login-stats") {
      contentType(ContentType.Application.Json)
      setBody(request)
    }
  }
}

private fun ConnectionMode.toLoginStatsConnectionMode(): LoginStatsConnectionMode =
    when (this) {
      ConnectionMode.DIRECT -> LoginStatsConnectionMode.DIRECT
      ConnectionMode.WEBVPN -> LoginStatsConnectionMode.WEBVPN
      ConnectionMode.SERVER_RELAY -> LoginStatsConnectionMode.SERVER_RELAY
    }
