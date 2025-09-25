package cn.edu.ubaa

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kotlin.test.*

class ApplicationTest {

    @Test
    fun testRoot() = testApplication {
        application {
            module()
        }
        val response = client.get("/")
        assertEquals(HttpStatusCode.OK, response.status)
        assertEquals("Ktor: ${Greeting().greet()}", response.bodyAsText())
    }

    @Test
    fun userInfoWithoutTokenReturnsUnauthorized() = testApplication {
        application {
            module()
        }

        val response = client.get("/api/v1/user/info")

        assertEquals(HttpStatusCode.Unauthorized, response.status)
        assertTrue(response.bodyAsText().contains("invalid_token"))
    }
}