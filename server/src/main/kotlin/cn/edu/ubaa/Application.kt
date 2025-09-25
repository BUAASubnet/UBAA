package cn.edu.ubaa

import cn.edu.ubaa.auth.authRouting
import cn.edu.ubaa.auth.JwtAuth.configureJwtAuth
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
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
    // Configure JWT Authentication
    configureJwtAuth()
    
    // Install the ContentNegotiation plugin to handle JSON serialization
    install(ContentNegotiation) {
        json()
    }

    routing {
        // Include the authentication routes
        authRouting()

        get("/") {
            call.respondText("Ktor: ${Greeting().greet()}")
        }
    }
}
