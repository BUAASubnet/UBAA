package cn.edu.ubaa

import cn.edu.ubaa.auth.JwtAuth
import cn.edu.ubaa.auth.JwtAuth.configureJwtAuth
import cn.edu.ubaa.auth.authRouting
import cn.edu.ubaa.bykc.bykcRouting
import cn.edu.ubaa.exam.examRouting
import cn.edu.ubaa.schedule.scheduleRouting
import cn.edu.ubaa.user.userRouting
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.response.*
import io.ktor.server.routing.*

fun main() {
    embeddedServer(Netty, port = SERVER_PORT, host = "0.0.0.0", module = Application::module)
            .start(wait = true)
}

fun Application.module() {
    // 配置 JWT 认证（安全性）
    configureJwtAuth()

    // 启用 JSON 序列化
    install(ContentNegotiation) { json() }

    routing {
        // 认证相关路由
        authRouting()

        authenticate(JwtAuth.JWT_AUTH) {
            userRouting()
            scheduleRouting()
            bykcRouting()
            examRouting()
        }

        get("/") { call.respondText("Ktor: ${Greeting().greet()}") }
    }
}
