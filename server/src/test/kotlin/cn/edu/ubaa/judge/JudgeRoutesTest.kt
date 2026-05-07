package cn.edu.ubaa.judge

import cn.edu.ubaa.module
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.contentType
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class JudgeRoutesTest {
  @Test
  fun `GET assignments without token returns unauthorized`() = testApplication {
    application { module() }

    val response = client.get("/api/v1/judge/assignments")

    assertEquals(HttpStatusCode.Unauthorized, response.status)
    assertTrue(response.bodyAsText().contains("invalid_token"))
    assertTrue(response.bodyAsText().contains("登录状态已失效，请重新登录"))
  }

  @Test
  fun `POST assignment details without token returns unauthorized`() = testApplication {
    application { module() }

    val response =
        client.post("/api/v1/judge/assignment-details") {
          contentType(ContentType.Application.Json)
          setBody("""{"keys":[{"courseId":"1","assignmentId":"101"}]}""")
        }

    assertEquals(HttpStatusCode.Unauthorized, response.status)
    assertTrue(response.bodyAsText().contains("invalid_token"))
    assertTrue(response.bodyAsText().contains("登录状态已失效，请重新登录"))
  }
}
