package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.parameter
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json

internal class LocalClassroomApiBackend : ClassroomApiBackend {
  private val json = Json { ignoreUnknownKeys = true }

  override suspend fun queryClassrooms(xqid: Int, date: String): Result<ClassroomQueryResponse> {
    if (LocalAuthSessionStore.get() == null) {
      return Result.failure(localUnauthenticatedApiException())
    }

    return try {
      syncLocalClassroomSession()
      val noRedirectClient = LocalUpstreamClientProvider.newNoRedirectClient()
      try {
        val response =
            noRedirectClient.get(
                localUpstreamUrl("https://app.buaa.edu.cn/buaafreeclass/wap/default/search1")
            ) {
              parameter("xqid", xqid)
              parameter("floorid", "")
              parameter("date", date)
              applyClassroomHeaders()
            }
        parseClassroomResponse(response)
      } finally {
        noRedirectClient.close()
      }
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("空闲教室查询失败，请稍后重试"))
    }
  }

  private suspend fun syncLocalClassroomSession() {
    try {
      LocalUpstreamClientProvider.shared().get(classroomSyncUrl()) {
        header(HttpHeaders.UserAgent, LOCAL_CLASSROOM_USER_AGENT)
      }
    } catch (_: Exception) {}
  }

  private suspend fun parseClassroomResponse(
      response: HttpResponse
  ): Result<ClassroomQueryResponse> {
    val body = response.bodyAsText()
    if (isLocalClassroomSessionExpired(response, body)) {
      return Result.failure(resolveLocalBusinessAuthenticationFailure("classroom_query_failed"))
    }
    if (response.status != HttpStatusCode.OK) {
      return Result.failure(
          localBusinessApiException(
              code = "classroom_query_failed",
              defaultMessage = "空闲教室查询失败，请稍后重试",
              status = response.status,
          )
      )
    }
    return try {
      Result.success(json.decodeFromString<ClassroomQueryResponse>(body))
    } catch (e: Exception) {
      Result.failure(e.toUserFacingApiException("空闲教室查询失败，请稍后重试"))
    }
  }
}

private fun isLocalClassroomSessionExpired(response: HttpResponse, body: String): Boolean {
  if (response.status == HttpStatusCode.Unauthorized) return true
  val location = response.headers[HttpHeaders.Location]
  if (localIsSsoUrl(location)) return true

  val trimmed = body.trimStart()
  if (trimmed.startsWith("<!DOCTYPE html", ignoreCase = true)) {
    return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
  }
  if (trimmed.startsWith("<html", ignoreCase = true)) {
    return body.contains("input name=\"execution\"") || body.contains("统一身份认证", ignoreCase = true)
  }
  return false
}

private fun io.ktor.client.request.HttpRequestBuilder.applyClassroomHeaders() {
  header(HttpHeaders.UserAgent, LOCAL_CLASSROOM_USER_AGENT)
  header(HttpHeaders.Accept, "application/json, text/javascript, */*; q=0.01")
  header(
      HttpHeaders.Referrer,
      localUpstreamUrl("https://app.buaa.edu.cn/site/classRoomQuery/index"),
  )
  header("X-Requested-With", "XMLHttpRequest")
}

private fun classroomSyncUrl(): String =
    localUpstreamUrl(
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn%2Fa_buaa%2Fapi%2Fcas%2Findex%3Fredirect%3Dhttps%253A%252F%252Fapp.buaa.edu.cn%252Fsite%252FclassRoomQuery%252Findex%26from%3Dwap%26login_from%3D&noAutoRedirect=1"
    )

private const val LOCAL_CLASSROOM_USER_AGENT =
    "Mozilla/5.0 (Linux; Android 16; 24031PN0DC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36 XWEB/1380275 MMWEBSDK/20230806 MMWEBID/4102 wxworklocal/3.2.200 wwlocal/3.2.200 wxwork/4.0.0 appname/wxworklocal-customized wxworklocal-device-code/195ef5586d7d3c2808fcbea32d77c0d4 MicroMessenger/7.0.1 appScheme/wxworklocalcustomized Language/zh_CN ColorScheme/Light WXWorklocalClientType/Android Brand/xiaomi"
