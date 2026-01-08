package cn.edu.ubaa

import cn.edu.ubaa.auth.JwtAuth
import cn.edu.ubaa.auth.JwtAuth.configureJwtAuth
import cn.edu.ubaa.auth.authRouting
import cn.edu.ubaa.bykc.bykcRouting
import cn.edu.ubaa.classroom.classroomRouting
import cn.edu.ubaa.evaluation.evaluationRouting
import cn.edu.ubaa.exam.examRouting
import cn.edu.ubaa.schedule.scheduleRouting
import cn.edu.ubaa.signin.signinRouting
import cn.edu.ubaa.user.userRouting
import io.github.cdimascio.dotenv.dotenv
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.auth.*
import io.ktor.server.engine.*
import io.ktor.server.metrics.micrometer.*
import io.ktor.server.netty.*
import io.ktor.server.plugins.calllogging.*
import io.ktor.server.plugins.contentnegotiation.*
import io.ktor.server.plugins.cors.routing.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.micrometer.prometheusmetrics.*
import org.slf4j.LoggerFactory
import org.slf4j.event.Level

/** 后端服务入口函数。 负责加载环境变量、配置服务器端口并启动 Netty 引擎。 */
fun main() {
  val dotenv = dotenv { ignoreIfMissing = true }
  val serverPort = dotenv["SERVER_PORT"]?.toInt() ?: 5432
  val serverHost = dotenv["SERVER_BIND_HOST"] ?: "0.0.0.0"

  val log = LoggerFactory.getLogger("Application")
  log.info("Starting UBAA Server on $serverHost:$serverPort...")

  embeddedServer(Netty, port = serverPort, host = serverHost, module = Application::module)
    .start(wait = true)
}

val log = LoggerFactory.getLogger("Application")

/** 全局 Prometheus 指标注册表。 */
val appMicrometerRegistry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)

/** Ktor 应用模块主配置。 负责安装插件（JWT, CORS, ContentNegotiation, Metrics）并注册业务路由。 */
fun Application.module() {
  log.info("Initializing Application module...")

  // 安装指标监控插件
  install(MicrometerMetrics) { registry = appMicrometerRegistry }

  // 安装请求日志插件
  install(CallLogging) { level = Level.INFO }

  // 配置 JWT 认证
  configureJwtAuth()

  // 配置跨域支持 (CORS)
  install(CORS) {
    allowMethod(HttpMethod.Options)
    allowMethod(HttpMethod.Put)
    allowMethod(HttpMethod.Delete)
    allowMethod(HttpMethod.Patch)
    allowHeader(HttpHeaders.Authorization)
    allowHeader(HttpHeaders.ContentType)
    allowHeader(HttpHeaders.AccessControlAllowOrigin)
    anyHost()
  }

  // 启用基于 Kotlinx Serialization 的 JSON 序列化
  install(ContentNegotiation) { json() }

  routing {
    /** 暴露 Prometheus 格式的指标。 */
    get("/metrics") { call.respondText(appMicrometerRegistry.scrape()) }

    // 1. 无需认证的路由（如登录、验证码）
    authRouting()

    // 2. 需 JWT 认证保护的业务路由
    authenticate(JwtAuth.JWT_AUTH) {
      log.info("Registering authenticated routes...")
      userRouting()
      scheduleRouting()
      bykcRouting()
      examRouting()
      signinRouting()
      classroomRouting()
      evaluationRouting()
    }

    /** 根路径健康检查。 */
    get("/") { call.respondText("Ktor: ${Greeting().greet()}") }
  }
  log.info("Application module initialized successfully.")
}
