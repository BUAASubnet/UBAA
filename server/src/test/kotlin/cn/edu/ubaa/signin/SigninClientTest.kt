package cn.edu.ubaa.signin

import cn.edu.ubaa.auth.InMemoryCookieStorageFactory
import cn.edu.ubaa.auth.InMemorySessionStore
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.VpnCipher
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.cookies.CookiesStorage
import io.ktor.client.request.forms.FormDataContent
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpMethod
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json

class SigninClientTest {

  @Test
  fun `sanitizeSignInMessage maps not in class time error`() {
    val client = SigninClient(studentId = "24182104")

    try {
      assertEquals(
          "当前不是上课时间，无法签到",
          client.sanitizeSignInMessage(success = false, rawMessage = "当前时间不是上课时间！"),
      )
    } finally {
      client.close()
    }
  }

  @Test
  fun `get classes follows iclass SSO redirects and app logs in with loginName`() = runBlocking {
    val originalVpnEnabled = VpnCipher.isEnabled
    VpnCipher.isEnabled = false
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    var myCenterRequests = 0
    val appLoginPhones = mutableListOf<String>()
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage ->
              HttpClient(MockEngine) {
                engine {
                  addHandler { request ->
                    when {
                      request.url.host == "iclass.buaa.edu.cn" &&
                          request.url.port == 8346 &&
                          request.url.parameters["type"] == "jumpMyCenter" -> {
                        myCenterRequests++
                        respond(
                            content = "",
                            status = HttpStatusCode.Found,
                            headers =
                                headersOf(
                                    HttpHeaders.Location,
                                    if (myCenterRequests == 1) {
                                      "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Ficlass.buaa.edu.cn%3A8346%2F%3Ftype%3DjumpMyCenter"
                                    } else {
                                      "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter"
                                    },
                                ),
                        )
                      }
                      request.url.host == "sso.buaa.edu.cn" ->
                          respond(
                              content = "",
                              status = HttpStatusCode.Found,
                              headers =
                                  headersOf(
                                      HttpHeaders.Location,
                                      "https://iclass.buaa.edu.cn:8346/cas-login?ticket=ST-test",
                                  ),
                          )
                      request.url.host == "iclass.buaa.edu.cn" &&
                          request.url.port == 8346 &&
                          request.url.encodedPath == "/cas-login" ->
                          respond(
                              content = "",
                              status = HttpStatusCode.Found,
                              headers =
                                  headersOf(HttpHeaders.Location, "/?type=jumpMyCenter#/MyCenter"),
                          )
                      else ->
                          error("Unexpected SSO request: ${request.method.value} ${request.url}")
                    }
                  }
                }
              }
            },
        )
    val appClient =
        HttpClient(MockEngine) {
          engine {
            addHandler { request ->
              when {
                request.url.host == "iclass.buaa.edu.cn" &&
                    request.url.port == 8347 &&
                    request.url.encodedPath == "/app/user/login.action" -> {
                  appLoginPhones += request.url.parameters["phone"].orEmpty()
                  respond(
                      content =
                          ByteReadChannel(
                              """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                          ),
                      status = HttpStatusCode.OK,
                      headers =
                          headersOf(
                              HttpHeaders.ContentType,
                              ContentType.Application.Json.toString(),
                          ),
                  )
                }
                request.url.toString() ==
                    "https://iclass.buaa.edu.cn:8347/app/course/get_stu_course_sched.action?id=user-1&dateStr=20260524" ->
                    respond(
                        content =
                            ByteReadChannel(
                                """{"STATUS":0,"result":[{"id":"course-1","courseName":"软件工程","classBeginTime":"08:00","classEndTime":"09:40","signStatus":0}]}"""
                            ),
                        status = HttpStatusCode.OK,
                        headers =
                            headersOf(
                                HttpHeaders.ContentType,
                                ContentType.Application.Json.toString(),
                            ),
                    )
                else -> error("Unexpected app request: ${request.method.value} ${request.url}")
              }
            }
          }
        }

    try {
      val candidate = sessionManager.prepareSession("24182104")
      sessionManager.commitSession(candidate, UserData("Test User", "24182104"))

      val client = SigninClient("24182104", sessionManager = sessionManager, client = appClient)
      val classes = client.getClasses("20260524")

      assertEquals(listOf(loginName), appLoginPhones)
      assertEquals(2, myCenterRequests)
      assertEquals("course-1", classes.singleOrNull()?.courseId)
    } finally {
      appClient.close()
      sessionManager.close()
      VpnCipher.isEnabled = originalVpnEnabled
    }
  }

  @Test
  fun `直连签到使用 8081 eschool 路径且保留提交参数`() = runBlocking { assertSigninRequest(useWebVpn = false) }

  @Test
  fun `WebVPN 签到使用 8347 app 路径且保留提交参数`() = runBlocking { assertSigninRequest(useWebVpn = true) }

  private suspend fun assertSigninRequest(useWebVpn: Boolean) {
    val originalVpnEnabled = VpnCipher.isEnabled
    VpnCipher.isEnabled = useWebVpn
    val expectedHost = if (useWebVpn) "d.buaa.edu.cn" else "iclass.buaa.edu.cn"
    val timestampUrl =
        if (useWebVpn) {
          "https://iclass.buaa.edu.cn:8347/app/common/get_timestamp.action"
        } else {
          "http://iclass.buaa.edu.cn:8081/app/common/get_timestamp.action"
        }
    val submitUrl =
        if (useWebVpn) {
          "https://iclass.buaa.edu.cn:8347/app/course/stu_scan_sign.action"
        } else {
          "http://iclass.buaa.edu.cn:8081/eschool/app/course/stu_scan_sign.action"
        }
    val loginName = "Rjc1QkJDMUMxNzVENkY0NkZCNzFDMEM5RjYwNzg4RDg="
    val sessionManager =
        SessionManager(
            sessionStore = InMemorySessionStore(),
            cookieStorageFactory = InMemoryCookieStorageFactory(),
            clientFactory = { _: CookiesStorage ->
              HttpClient(MockEngine) {
                engine {
                  addHandler { request ->
                    assertEquals(expectedHost, request.url.host)
                    val upstreamUrl = Url(VpnCipher.fromVpnUrl(request.url.toString()))
                    when {
                      upstreamUrl.host == "iclass.buaa.edu.cn" &&
                          upstreamUrl.port == 8346 &&
                          upstreamUrl.parameters["type"] == "jumpMyCenter" ->
                          respond(
                              content = "",
                              status = HttpStatusCode.Found,
                              headers =
                                  headersOf(
                                      HttpHeaders.Location,
                                      "https://iclass.buaa.edu.cn:8346/?loginName=$loginName&type=jumpMyCenter#/MyCenter",
                                  ),
                          )
                      else -> error("未预期的 SSO 请求：${request.method.value} ${request.url}")
                    }
                  }
                }
              }
            },
        )
    val appClient =
        HttpClient(MockEngine) {
          install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
          engine {
            addHandler { request ->
              assertEquals(expectedHost, request.url.host)
              val upstreamUrl = Url(VpnCipher.fromVpnUrl(request.url.toString()))
              when {
                upstreamUrl.host == "iclass.buaa.edu.cn" &&
                    upstreamUrl.port == 8347 &&
                    upstreamUrl.encodedPath == "/app/user/login.action" -> {
                  assertEquals(loginName, request.url.parameters["phone"])
                  respond(
                      content =
                          ByteReadChannel(
                              """{"STATUS":0,"result":{"id":"user-1","sessionId":"session-1"}}"""
                          ),
                      status = HttpStatusCode.OK,
                      headers =
                          headersOf(
                              HttpHeaders.ContentType,
                              ContentType.Application.Json.toString(),
                          ),
                  )
                }
                upstreamUrl.toString() == timestampUrl ->
                    respond(
                        content = ByteReadChannel("""{"timestamp":"1713600000"}"""),
                        status = HttpStatusCode.OK,
                        headers =
                            headersOf(
                                HttpHeaders.ContentType,
                                ContentType.Application.Json.toString(),
                            ),
                    )
                upstreamUrl.toString() ==
                    "$submitUrl?courseSchedId=course-1&timestamp=1713600000" -> {
                  assertEquals(HttpMethod.Post, request.method)
                  assertEquals("session-1", request.headers["sessionId"])
                  assertEquals("user-1", assertIs<FormDataContent>(request.body).formData["id"])
                  respond(
                      content =
                          ByteReadChannel(
                              """{"STATUS":0,"ERRMSG":"签到成功","result":{"stuSignStatus":1}}"""
                          ),
                      status = HttpStatusCode.OK,
                      headers =
                          headersOf(
                              HttpHeaders.ContentType,
                              ContentType.Application.Json.toString(),
                          ),
                  )
                }
                // 与真实上游一致，带有 /eschool 的 8347 请求不能返回签到成功。
                upstreamUrl
                    .toString()
                    .startsWith(
                        "https://iclass.buaa.edu.cn:8347/eschool/app/course/stu_scan_sign.action"
                    ) ->
                    respond(
                        content = ByteReadChannel("<html><title>404 Not Found</title></html>"),
                        status = HttpStatusCode.NotFound,
                        headers =
                            headersOf(HttpHeaders.ContentType, ContentType.Text.Html.toString()),
                    )
                else -> error("未预期的 app 请求：${request.method.value} ${request.url}")
              }
            }
          }
        }

    try {
      val candidate = sessionManager.prepareSession("24182104")
      sessionManager.commitSession(candidate, UserData("Test User", "24182104"))

      val client = SigninClient("24182104", sessionManager = sessionManager, client = appClient)
      val result = client.signIn("course-1")

      assertTrue(result.first, result.second)
      assertEquals("签到成功", result.second)
    } finally {
      appClient.close()
      sessionManager.close()
      VpnCipher.isEnabled = originalVpnEnabled
    }
  }
}
