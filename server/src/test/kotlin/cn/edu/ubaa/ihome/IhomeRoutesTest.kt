package cn.edu.ubaa.ihome

import cn.edu.ubaa.module
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.server.testing.testApplication
import kotlin.test.Test
import kotlin.test.assertEquals

class IhomeRoutesTest {
  @Test
  fun `读取与写入路由都要求有效登录`() = testApplication {
    application { module() }
    for (path in listOf("appeals", "appeals/42", "config", "notices", "notices/1")) {
      assertEquals(HttpStatusCode.Unauthorized, client.get("/api/v1/ihome/$path").status)
    }
    assertEquals(
        HttpStatusCode.Unauthorized,
        client
            .post("/api/v1/ihome/appeals/42/reaction") {
              contentType(ContentType.Application.Json)
              setBody("""{"reaction":"FOLLOW","enabled":true}""")
            }
            .status,
    )
  }
}
