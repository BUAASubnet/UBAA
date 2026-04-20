package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.model.evaluation.EvaluationCourse
import com.russhwolf.settings.MapSettings
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.cookies.HttpCookies
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.utils.io.ByteReadChannel
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

class LocalEvaluationServiceBackendTest {
  @BeforeTest
  fun setup() {
    runTest { localConnectionTestMutex.lock() }
    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    ConnectionRuntime.resolveSelectedMode()
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Test User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )
    LocalUpstreamClientProvider.reset()
  }

  @AfterTest
  fun tearDown() {
    LocalUpstreamClientProvider.reset()
    LocalAuthSessionStore.clearAllScopes()
    LocalCookieStore.clearAllScopes()
    ConnectionRuntime.clearSelectedMode()
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
    localConnectionTestMutex.unlock()
  }

  @Test
  fun `local evaluation service fetches courses from direct upstream`() = runTest {
    val engine =
        MockEngine { request ->
          when {
            request.url.host == "spoc.buaa.edu.cn" && request.url.encodedPath == "/pjxt/cas" ->
                respond(
                    content = ByteReadChannel.Empty,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "text/html"),
                )
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/component/queryXnxq" ->
                respondJson(
                    """{"code":200,"content":[{"xn":"2025-2026","xq":"1"}]}"""
                )
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks" -> {
              assertEquals("22373333", request.url.parameters["yhdm"])
              respondJson("""{"code":200,"result":{"list":[{"rwid":"rw1","rwmc":"2026春评教"}]}}""")
            }
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/evaluationMethodSix/getQuestionnaireListToTask" -> {
              assertEquals("rw1", request.url.parameters["rwid"])
              respondJson("""{"code":200,"result":[{"wjid":"wj1","wjmc":"教学评价","msid":"2"}]}""")
            }
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/evaluationMethodSix/reviseQuestionnairePattern" ->
                respondJson("""{"code":200}""")
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/evaluationMethodSix/getRequiredReviewsData" &&
                request.url.parameters["sfyp"] == "0" ->
                respondJson(
                    """
                    {
                      "code": 200,
                      "result": [
                        {
                          "kcdm": "CS101",
                          "kcmc": "操作系统",
                          "bpmc": "李老师",
                          "bpdm": "T001",
                          "pjrdm": "22373333",
                          "pjrmc": "测试学生",
                          "zdmc": "STID",
                          "ypjcs": 0,
                          "xypjcs": 1,
                          "sxz": "1",
                          "rwh": "rwh-1",
                          "xn": "2025-2026",
                          "xq": "1",
                          "pjlxid": "2",
                          "sfksqbpj": "1",
                          "yxsfktjst": "0"
                        }
                      ]
                    }
                    """.trimIndent()
                )
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/evaluationMethodSix/getRequiredReviewsData" &&
                request.url.parameters["sfyp"] == "1" ->
                respondJson(
                    """
                    {
                      "code": 200,
                      "result": [
                        {
                          "kcdm": "CS102",
                          "kcmc": "编译原理",
                          "bpmc": "王老师",
                          "bpdm": "T002",
                          "pjrdm": "22373333",
                          "pjrmc": "测试学生"
                        }
                      ]
                    }
                    """.trimIndent()
                )
            else -> error("Unexpected url: ${request.url}")
          }
        }
    useMockUpstream(engine)

    val result = LocalEvaluationServiceBackend().getAllEvaluations()

    assertTrue(result.isSuccess)
    val response = result.getOrNull()
    assertEquals(2, response?.courses?.size)
    assertEquals(2, response?.progress?.totalCourses)
    assertEquals(1, response?.progress?.pendingCourses)
    assertEquals(1, response?.progress?.evaluatedCourses)
    assertEquals(false, response?.courses?.firstOrNull()?.isEvaluated)
    assertEquals(true, response?.courses?.lastOrNull()?.isEvaluated)
    assertEquals("rw1_wj1_CS101_T001", response?.courses?.firstOrNull()?.id)
    assertEquals("2025-20261", response?.courses?.firstOrNull()?.xnxq)
    assertEquals("2", response?.courses?.firstOrNull()?.msid)
  }

  @Test
  fun `local evaluation service submits evaluation through direct upstream`() = runTest {
    val engine =
        MockEngine { request ->
          when {
            request.url.host == "spoc.buaa.edu.cn" && request.url.encodedPath == "/pjxt/cas" ->
                respond(
                    content = ByteReadChannel.Empty,
                    status = HttpStatusCode.OK,
                    headers = headersOf(HttpHeaders.ContentType, "text/html"),
                )
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/evaluationMethodSix/reviseQuestionnairePattern" ->
                respondJson("""{"code":200}""")
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/evaluationMethodSix/getQuestionnaireTopic" -> {
              assertEquals("rw1", request.url.parameters["rwid"])
              assertEquals("wj1", request.url.parameters["wjid"])
              assertEquals("CS101", request.url.parameters["kcdm"])
              respondJson(
                  """
                  {
                    "code": 200,
                    "result": [
                      {
                        "pjxtWjWjbReturnEntity": {
                          "wjzblist": [
                            {
                              "tklist": [
                                {
                                  "tmlx": "1",
                                  "tmid": "q1",
                                  "tmxxlist": [
                                    {"tmxxid": "optA"},
                                    {"tmxxid": "optB"}
                                  ]
                                }
                              ]
                            }
                          ]
                        },
                        "pjxtPjjgPjjgckb": [
                          {
                            "wjssrwid": "ssrw1",
                            "bprdm": "T001",
                            "bprmc": "李老师",
                            "kcdm": "CS101",
                            "kcmc": "操作系统",
                            "pjfs": "1",
                            "pjid": "pj1",
                            "pjlx": "2",
                            "pjrdm": "22373333",
                            "pjrjsdm": "22373333",
                            "pjrxm": "测试学生",
                            "xnxq": "2025-20261",
                            "sfxxpj": "1"
                          }
                        ],
                        "pjmap": {"source": "test"}
                      }
                    ]
                  }
                  """.trimIndent()
              )
            }
            request.url.host == "spoc.buaa.edu.cn" &&
                request.url.encodedPath == "/pjxt/evaluationMethodSix/submitSaveEvaluation" ->
                respondJson("""{"code":200,"message":"提交成功","result":{}}""")
            else -> error("Unexpected url: ${request.url}")
          }
        }
    useMockUpstream(engine)

    val result =
        LocalEvaluationServiceBackend()
            .submitEvaluations(
                listOf(
                    EvaluationCourse(
                        id = "rw1_wj1_CS101_T001",
                        kcmc = "操作系统",
                        bpmc = "李老师",
                        rwid = "rw1",
                        wjid = "wj1",
                        kcdm = "CS101",
                        bpdm = "T001",
                        pjrdm = "22373333",
                        pjrmc = "测试学生",
                        xnxq = "2025-20261",
                        msid = "2",
                        zdmc = "STID",
                        ypjcs = 0,
                        xypjcs = 1,
                        sxz = "1",
                        rwh = "rwh-1",
                        xn = "2025-2026",
                        xq = "1",
                        pjlxid = "2",
                        sfksqbpj = "1",
                        yxsfktjst = "0",
                    )
                )
            )

    assertEquals(1, result.size)
    assertEquals(true, result.single().success)
    assertEquals("评教成功", result.single().message)
    assertEquals("操作系统", result.single().courseName)
  }

  private fun useMockUpstream(engine: MockEngine) {
    LocalUpstreamClientProvider.clientFactory = { followRedirects ->
      HttpClient(engine) {
        this.followRedirects = followRedirects
        install(HttpCookies) { storage = LocalCookieStore.storage(ConnectionMode.DIRECT) }
      }
    }
  }
}

private fun MockRequestHandleScope.respondJson(body: String) =
    respond(
        content = ByteReadChannel(body),
        status = HttpStatusCode.OK,
        headers = headersOf(HttpHeaders.ContentType, ContentType.Application.Json.toString()),
    )
