package cn.edu.ubaa.api

import cn.edu.ubaa.api.feature.IhomeException
import cn.edu.ubaa.api.feature.IhomeUpstreamClient
import cn.edu.ubaa.api.local.LocalWebVpnSupport
import cn.edu.ubaa.model.dto.*
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.*
import io.ktor.client.plugins.logging.*
import io.ktor.client.request.HttpRequestData
import io.ktor.http.*
import io.ktor.http.content.TextContent
import kotlin.test.*
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest

class IhomeUpstreamClientTest {
  private fun ok(data: String) =
      """{"code":20000,"success":true,"error":"","message":"success","data":$data}"""

  private fun appeal(followed: Int = 0) =
      """{"id":42,"content":"合成诉求","is_follow":$followed,"follow_count":$followed,"is_praise":0,"praise_count":0}"""

  private val jsonHeaders = headersOf(HttpHeaders.ContentType, "application/json")

  @Test
  fun `真实WebVPN编码的CAS回调可提取片段令牌而不循环加载web页面`() = runTest {
    val requests = mutableListOf<HttpRequestData>()
    var callbacks = 0
    val wrappedIhome =
        "https://d.buaa.edu.cn/http/77726476706e69737468656265737421f9b94389263126557a1dc7af96"
    val base =
        HttpClient(
            MockEngine { request ->
              requests += request
              assertEquals("d.buaa.edu.cn", request.url.host)
              assertEquals("https", request.url.protocol.name)
              when {
                request.url.encodedPath.endsWith("/login") -> {
                  assertEquals(
                      "http://i.buaa.edu.cn/api/authLogin",
                      request.url.parameters["service"],
                  )
                  respond(
                      "",
                      HttpStatusCode.Found,
                      headersOf(
                          HttpHeaders.Location,
                          "$wrappedIhome/api/authLogin?ticket=fixture-ticket",
                      ),
                  )
                }
                request.url.encodedPath.endsWith("/api/authLogin") -> {
                  callbacks++
                  assertEquals(
                      if (callbacks == 1) setOf("ticket") else emptySet(),
                      request.url.parameters.names(),
                  )
                  respond(
                      "",
                      HttpStatusCode.Found,
                      headersOf(
                          HttpHeaders.Location,
                          if (callbacks == 1) "$wrappedIhome/api/authLogin"
                          else "$wrappedIhome/web/#/login?type=0&token=fixture-token",
                      ),
                  )
                }
                request.url.encodedPath.endsWith("/web") ->
                    respond(
                        "",
                        HttpStatusCode.MovedPermanently,
                        headersOf(HttpHeaders.Location, "$wrappedIhome/web/"),
                    )
                else -> {
                  assertTrue(request.url.encodedPath.endsWith("/api/appeal/42"))
                  assertEquals("Bearer fixture-token", request.headers[HttpHeaders.Authorization])
                  respond(ok(appeal()), headers = jsonHeaders)
                }
              }
            }
        )
    val client =
        IhomeUpstreamClient(
            base,
            LocalWebVpnSupport::toWebVpnUrl,
            LocalWebVpnSupport::fromWebVpnUrl,
        )
    try {
      assertEquals(42L, client.getDetail(42).id)
      assertEquals(4, requests.size)
      assertEquals(2, callbacks)
      assertTrue(requests.take(3).all { it.headers[HttpHeaders.Authorization] == null })
      assertTrue(
          requests.none { it.url.encodedPath.contains("/web") || it.url.fragment.isNotEmpty() }
      )
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `WebVPN登录和业务请求始终保持所选路由`() = runTest {
    val urls = mutableListOf<Url>()
    val base =
        HttpClient(
            MockEngine { request ->
              urls += request.url
              if (request.url.encodedPath.contains("/sso.buaa.edu.cn/"))
                  respond(
                      "",
                      HttpStatusCode.Found,
                      headersOf(
                          HttpHeaders.Location,
                          "http://i.buaa.edu.cn/web/#/login?type=0&token=fixture-token",
                      ),
                  )
              else respond(ok(appeal()), headers = jsonHeaders)
            }
        )
    val client =
        IhomeUpstreamClient(
            base,
            route = { "https://vpn.test/" + it.substringAfter("://") },
            unroute = {
              if (it.startsWith("https://vpn.test/"))
                  "https://" + it.removePrefix("https://vpn.test/")
              else it
            },
        )
    try {
      client.getDetail(42)
      assertTrue(urls.all { it.host == "vpn.test" })
      assertEquals(2, urls.size)
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `读取401只重新认证一次且模块日志不包含凭据`() = runTest {
    var logins = 0
    var reads = 0
    val logs = mutableListOf<String>()
    val base =
        HttpClient(
            MockEngine { request ->
              if (request.url.host == "sso.buaa.edu.cn") {
                logins++
                respond(
                    "",
                    HttpStatusCode.Found,
                    headersOf(
                        HttpHeaders.Location,
                        "https://i.buaa.edu.cn/web/#/login?type=0&token=secret-fixture-$logins",
                    ),
                )
              } else {
                reads++
                if (reads == 1) respond("{}", HttpStatusCode.Unauthorized, jsonHeaders)
                else respond(ok(appeal()), headers = jsonHeaders)
              }
            }
        ) {
          install(Logging) {
            level = LogLevel.ALL
            logger =
                object : Logger {
                  override fun log(message: String) {
                    logs += message
                  }
                }
          }
        }
    val client = IhomeUpstreamClient(base)
    try {
      client.getDetail(42)
      assertEquals(2, logins)
      assertEquals(2, reads)
      assertFalse(logs.any { it.contains("secret-fixture") || it.contains("Bearer") })
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `CAS片段令牌仅发送至业务请求并保留原service`() = runTest {
    val requests = mutableListOf<HttpRequestData>()
    var callback = 0
    val base =
        HttpClient(
            MockEngine { request ->
              requests += request
              when (request.url.encodedPath) {
                "/login" -> {
                  assertEquals(
                      "http://i.buaa.edu.cn/api/authLogin",
                      request.url.parameters["service"],
                  )
                  respond(
                      "",
                      HttpStatusCode.Found,
                      headersOf(
                          HttpHeaders.Location,
                          "http://i.buaa.edu.cn/api/authLogin?ticket=fixture-ticket",
                      ),
                  )
                }
                "/api/authLogin" -> {
                  assertEquals("https", request.url.protocol.name)
                  callback++
                  assertEquals(
                      if (callback == 1) setOf("ticket") else emptySet(),
                      request.url.parameters.names(),
                  )
                  if (callback == 1)
                      assertEquals("fixture-ticket", request.url.parameters["ticket"])
                  respond(
                      "",
                      HttpStatusCode.Found,
                      headersOf(
                          HttpHeaders.Location,
                          if (callback == 1) "/api/authLogin"
                          else "http://i.buaa.edu.cn/web/#/login?type=0&token=fixture-token",
                      ),
                  )
                }
                else -> {
                  assertEquals("Bearer fixture-token", request.headers[HttpHeaders.Authorization])
                  assertEquals("校园 回复", request.url.parameters["keyword"])
                  respond(
                      ok("""{"current_page":1,"last_page":1,"total":1,"data":[${appeal()}]}"""),
                      headers = jsonHeaders,
                  )
                }
              }
            }
        )
    val client = IhomeUpstreamClient(base)
    try {
      assertEquals(42, client.getPage(IhomeQuery(keyword = "校园 回复")).entries.single().appeal.id)
      assertTrue(requests.take(3).all { it.headers[HttpHeaders.Authorization] == null })
      assertEquals(4, requests.size)
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `登录服务500不误报账号失效`() = runTest {
    val base = HttpClient(MockEngine { respond("服务暂时异常", HttpStatusCode.InternalServerError) })
    val client = IhomeUpstreamClient(base)
    try {
      val error = assertFailsWith<IhomeException> { client.getDetail(42) }
      assertEquals("ihome_upstream", error.code)
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `外部登录跳转被阻止且不跟随业务重定向`() = runTest {
    var requests = 0
    val base =
        HttpClient(
            MockEngine {
              requests++
              respond(
                  "",
                  HttpStatusCode.Found,
                  headersOf(HttpHeaders.Location, "https://example.org/steal?token=fixture"),
              )
            }
        )
    val client = IhomeUpstreamClient(base)
    try {
      assertFailsWith<IhomeException> { client.getDetail(42) }
      assertEquals(1, requests)
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `关注提交响应丢失时回查且重复目标不会二次切换`() = runTest {
    var followed = 0
    var posts = 0
    val base =
        HttpClient(
            MockEngine { request ->
              when {
                request.url.host == "sso.buaa.edu.cn" ->
                    respond(
                        "",
                        HttpStatusCode.Found,
                        headersOf(
                            HttpHeaders.Location,
                            "https://i.buaa.edu.cn/web/#/login?type=0&token=fixture-token",
                        ),
                    )
                request.method == HttpMethod.Post -> {
                  posts++
                  assertEquals("/api/appeal_follow/42", request.url.encodedPath)
                  assertEquals("{}", (request.body as TextContent).text)
                  followed = 1
                  throw IllegalStateException("模拟响应丢失，不应向用户暴露")
                }
                else -> respond(ok(appeal(followed)), headers = jsonHeaders)
              }
            }
        )
    val client = IhomeUpstreamClient(base)
    try {
      val one = async { client.setReaction(42, IhomeReactionRequest(IhomeReaction.FOLLOW, true)) }
      val two = async { client.setReaction(42, IhomeReactionRequest(IhomeReaction.FOLLOW, true)) }
      assertTrue(one.await().confirmed)
      assertTrue(two.await().confirmed)
      assertEquals(1, posts)
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `写后回查失败保持未确认且不自动重发`() = runTest {
    var posted = false
    var posts = 0
    val base =
        HttpClient(
            MockEngine { request ->
              when {
                request.url.host == "sso.buaa.edu.cn" ->
                    respond(
                        "",
                        HttpStatusCode.Found,
                        headersOf(
                            HttpHeaders.Location,
                            "https://i.buaa.edu.cn/web/#/login?type=0&token=fixture-token",
                        ),
                    )
                request.method == HttpMethod.Post -> {
                  posts++
                  posted = true
                  throw IllegalStateException("断网")
                }
                posted -> throw IllegalStateException("仍然断网")
                else -> respond(ok(appeal()), headers = jsonHeaders)
              }
            }
        )
    val client = IhomeUpstreamClient(base)
    try {
      val result = client.setReaction(42, IhomeReactionRequest(IhomeReaction.FOLLOW, true))
      assertFalse(result.confirmed)
      assertNull(result.appeal)
      assertEquals(1, posts)
    } finally {
      client.close()
      base.close()
    }
  }

  @Test
  fun `本人详情与个人筛选使用独立路径参数`() = runTest {
    val business = mutableListOf<HttpRequestData>()
    val base =
        HttpClient(
            MockEngine { request ->
              if (request.url.host == "sso.buaa.edu.cn")
                  respond(
                      "",
                      HttpStatusCode.Found,
                      headersOf(
                          HttpHeaders.Location,
                          "https://i.buaa.edu.cn/web/#/login?type=0&token=fixture-token",
                      ),
                  )
              else {
                business += request
                respond(
                    ok(
                        if (request.url.encodedPath.endsWith("/42")) appeal()
                        else """{"current_page":2,"last_page":3,"total":6,"data":[]}"""
                    ),
                    headers = jsonHeaders,
                )
              }
            }
        )
    val client = IhomeUpstreamClient(base)
    try {
      client.getDetail(42, true)
      client.getPage(
          IhomeQuery(scope = IhomeScope.MINE, page = 2, limit = 2, filter = IhomeFilter.UNREPLIED)
      )
      assertEquals("/api/appeal/my_appreal/42", business[0].url.encodedPath)
      assertEquals("0", business[1].url.parameters["is_reply"])
      assertNull(business[1].url.parameters["reply"])
      assertEquals("2", business[1].url.parameters["page"])
    } finally {
      client.close()
      base.close()
    }
  }
}
