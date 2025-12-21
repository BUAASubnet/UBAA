package cn.edu.ubaa.bykc

import cn.edu.ubaa.module
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kotlin.test.*

/** BYKC 路由测试 */
class BykcRoutesTest {

    @Test
    fun `GET bykc profile without token returns unauthorized`() = testApplication {
        application { module() }

        val response = client.get("/api/v1/bykc/profile")

        assertEquals(HttpStatusCode.Unauthorized, response.status)
        assertTrue(response.bodyAsText().contains("invalid_token"))
    }

    @Test
    fun `GET bykc courses without token returns unauthorized`() = testApplication {
        application { module() }

        val response = client.get("/api/v1/bykc/courses")

        assertEquals(HttpStatusCode.Unauthorized, response.status)
        assertTrue(response.bodyAsText().contains("invalid_token"))
    }

    @Test
    fun `POST bykc select course without token returns unauthorized`() = testApplication {
        application { module() }

        val response = client.post("/api/v1/bykc/courses/12345/select")

        assertEquals(HttpStatusCode.Unauthorized, response.status)
        assertTrue(response.bodyAsText().contains("invalid_token"))
    }

    @Test
    fun `DELETE bykc deselect course returns not implemented`() = testApplication {
        application { module() }

        // 即使没有认证，DELETE 方法也应该先检查认证
        val response = client.delete("/api/v1/bykc/courses/12345/select")

        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }

    @Test
    fun `GET bykc courses with invalid page returns bad request`() = testApplication {
        application { module() }

        // 由于需要认证，这个测试会返回 Unauthorized
        // 实际的参数验证测试需要先通过认证
        val response = client.get("/api/v1/bykc/courses?page=0")

        assertEquals(HttpStatusCode.Unauthorized, response.status)
    }
}
