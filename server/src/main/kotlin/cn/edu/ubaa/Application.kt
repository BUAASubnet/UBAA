package cn.edu.ubaa

import cn.edu.ubaa.auth.JwtAuth
import cn.edu.ubaa.auth.JwtAuth.configureJwtAuth
import cn.edu.ubaa.auth.authRouting
import cn.edu.ubaa.bykc.bykcRouting
import cn.edu.ubaa.classroom.classroomRouting
import cn.edu.ubaa.exam.examRouting
import cn.edu.ubaa.schedule.scheduleRouting
import cn.edu.ubaa.signin.signinRouting
import cn.edu.ubaa.user.userRouting
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.http.*
import org.slf4j.LoggerFactory

fun main() {
    val log = LoggerFactory.getLogger("Application")
    log.info("Starting UBAA Server...")
    // 启动前自动检测网络环境
    // VpnCipher.autoDetectEnvironment()

    embeddedServer(Netty, port = SERVER_PORT, host = "0.0.0.0", module = Application::module)
            .start(wait = true)
}

fun Application.module() {
    log.info("Initializing Application module...")
    // 配置 JWT 认证（安全性）
    configureJwtAuth()

    // 配置 CORS
    install(CORS) {
        allowMethod(HttpMethod.Options)
        allowMethod(HttpMethod.Put)
        allowMethod(HttpMethod.Delete)
        allowMethod(HttpMethod.Patch)
        allowHeader(HttpHeaders.Authorization)
        allowHeader(HttpHeaders.ContentType)
        allowHeader(HttpHeaders.AccessControlAllowOrigin)
        anyHost() // 或者 allowHost("localhost:8080")
    }

    // 启用 JSON 序列化
    install(ContentNegotiation) { json() }

    routing {
        // 认证相关路由
        authRouting()

        authenticate(JwtAuth.JWT_AUTH) {
            log.info("Registering authenticated routes...")
            userRouting()
            scheduleRouting()
            bykcRouting()
            examRouting()
            signinRouting()
            classroomRouting()
        }

        get("/") {
            log.info("Root endpoint accessed")
            call.respondText("Ktor: ${Greeting().greet()}")
        }
    }
    log.info("Application module initialized successfully.")
}
