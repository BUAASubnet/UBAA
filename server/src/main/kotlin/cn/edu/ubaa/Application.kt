package cn.edu.ubaa

import cn.edu.ubaa.auth.GlobalAcademicPortalWarmupCoordinator
import cn.edu.ubaa.auth.GlobalRefreshTokenService
import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.JwtAuth
import cn.edu.ubaa.auth.JwtAuth.configureJwtAuth
import cn.edu.ubaa.auth.authRouting
import cn.edu.ubaa.auth.configureGlobalErrorHandling
import cn.edu.ubaa.bykc.GlobalBykcService
import cn.edu.ubaa.bykc.bykcRouting
import cn.edu.ubaa.cgyy.GlobalCgyyService
import cn.edu.ubaa.cgyy.cgyyRouting
import cn.edu.ubaa.classroom.classroomRouting
import cn.edu.ubaa.evaluation.evaluationRouting
import cn.edu.ubaa.exam.examRouting
import cn.edu.ubaa.metrics.AppObservability
import cn.edu.ubaa.metrics.GaugeBindings
import cn.edu.ubaa.metrics.LoginMetricsRecorder
import cn.edu.ubaa.metrics.RedisLoginStatsStore
import cn.edu.ubaa.schedule.scheduleRouting
import cn.edu.ubaa.signin.SigninService
import cn.edu.ubaa.signin.signinRouting
import cn.edu.ubaa.spoc.GlobalSpocService
import cn.edu.ubaa.spoc.spocRouting
import cn.edu.ubaa.user.userRouting
import cn.edu.ubaa.utils.HeadlessImageSupport
import cn.edu.ubaa.version.AppVersionService
import cn.edu.ubaa.version.GlobalAppVersionService
import cn.edu.ubaa.version.appVersionRouting
import cn.edu.ubaa.ygdk.GlobalYgdkService
import cn.edu.ubaa.ygdk.ygdkRouting
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
import kotlin.time.Duration.Companion.minutes
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.slf4j.LoggerFactory
import org.slf4j.event.Level

/** 后端服务入口函数。 负责加载环境变量、配置服务器端口并启动 Netty 引擎。 */
fun main() {
  HeadlessImageSupport.ensureConfigured()
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
/** Ktor 应用模块主配置。 负责安装插件（JWT, CORS, ContentNegotiation, Metrics）并注册业务路由。 */
fun Application.module() {
  val metricsRegistry = PrometheusMeterRegistry(PrometheusConfig.DEFAULT)
  val loginMetricsRecorder = LoginMetricsRecorder(RedisLoginStatsStore(), metricsRegistry)
  module(metricsRegistry, loginMetricsRecorder, GlobalAppVersionService.instance)
}

internal fun Application.module(
    metricsRegistry: PrometheusMeterRegistry,
    loginMetricsRecorder: LoginMetricsRecorder,
    appVersionService: AppVersionService = GlobalAppVersionService.instance,
) {
  log.info("Initializing Application module...")
  AppObservability.initialize(metricsRegistry)
  loginMetricsRecorder.bindMetrics()

  install(MicrometerMetrics) { registry = metricsRegistry }
  install(CallLogging) { level = Level.INFO }
  configureJwtAuth()

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

  install(ContentNegotiation) { json() }
  configureGlobalErrorHandling()

  val sessionManager = GlobalSessionManager.instance
  val bykcService = GlobalBykcService.instance
  val cgyyService = GlobalCgyyService.instance
  val spocService = GlobalSpocService.instance
  val ygdkService = GlobalYgdkService.instance
  registerPerformanceGauges(
      metricsRegistry,
      sessionManager,
      bykcService,
      cgyyService,
      spocService,
      ygdkService,
  )

  val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
  cleanupScope.launch {
    while (isActive) {
      delay(5.minutes)
      val expiredSessions = sessionManager.cleanupExpiredSessions()
      val expiredPreLogin = sessionManager.cleanupExpiredPreLoginSessions()
      val expiredSigninClients = SigninService.cleanupExpiredClients()
      val expiredBykcClients = bykcService.cleanupExpiredClients()
      val expiredCgyyClients = cgyyService.cleanupExpiredClients()
      val expiredSpocClients = spocService.cleanupExpiredClients()
      val expiredYgdkClients = ygdkService.cleanupExpiredClients()
      AppObservability.recordCleanupRemovals("session", expiredSessions)
      AppObservability.recordCleanupRemovals("prelogin", expiredPreLogin)
      AppObservability.recordCleanupRemovals("signin_client", expiredSigninClients)
      AppObservability.recordCleanupRemovals("bykc_client", expiredBykcClients)
      AppObservability.recordCleanupRemovals("cgyy_client", expiredCgyyClients)
      AppObservability.recordCleanupRemovals("spoc_client", expiredSpocClients)
      AppObservability.recordCleanupRemovals("ygdk_client", expiredYgdkClients)
      if (
          expiredSessions +
              expiredPreLogin +
              expiredSigninClients +
              expiredBykcClients +
              expiredCgyyClients +
              expiredSpocClients +
              expiredYgdkClients > 0
      ) {
        log.info(
            "Cleanup removed sessions={}, prelogin={}, signinClients={}, bykcClients={}, cgyyClients={}, spocClients={}, ygdkClients={}",
            expiredSessions,
            expiredPreLogin,
            expiredSigninClients,
            expiredBykcClients,
            expiredCgyyClients,
            expiredSpocClients,
            expiredYgdkClients,
        )
      }
    }
  }

  monitor.subscribe(ApplicationStopping) {
    cleanupScope.cancel()
    SigninService.closeAll()
    bykcService.clearCache()
    cgyyService.clearCache()
    spocService.clearCache()
    ygdkService.clearCache()
    GlobalAcademicPortalWarmupCoordinator.close()
    sessionManager.close()
    GlobalAppVersionService.release(appVersionService)
    GlobalRefreshTokenService.instance.close()
    loginMetricsRecorder.close()
    AppObservability.reset(metricsRegistry)
  }

  routing {
    get("/metrics") { call.respondText(metricsRegistry.scrape()) }

    appVersionRouting(appVersionService)
    authRouting(loginMetricsRecorder)

    authenticate(JwtAuth.JWT_AUTH) {
      log.info("Registering authenticated routes...")
      userRouting()
      scheduleRouting()
      bykcRouting()
      examRouting()
      signinRouting()
      classroomRouting()
      cgyyRouting()
      evaluationRouting()
      spocRouting()
      ygdkRouting()
    }

    get("/") { call.respondText("Ktor: ${Greeting().greet()}") }
  }
  log.info("Application module initialized successfully.")
}

internal fun registerPerformanceGauges(
    metricsRegistry: PrometheusMeterRegistry,
    sessionManager: cn.edu.ubaa.auth.SessionManager,
    bykcService: cn.edu.ubaa.bykc.BykcService,
    cgyyService: cn.edu.ubaa.cgyy.CgyyService,
    spocService: cn.edu.ubaa.spoc.SpocService,
    ygdkService: cn.edu.ubaa.ygdk.YgdkService,
) {
  GaugeBindings.bind(metricsRegistry, "ubaa.sessions.active") {
    sessionManager.activeSessionCount().toDouble()
  }
  GaugeBindings.bind(metricsRegistry, "ubaa.sessions.prelogin") {
    sessionManager.preLoginSessionCount().toDouble()
  }
  GaugeBindings.bind(metricsRegistry, "ubaa.signin.cache") { SigninService.cacheSize().toDouble() }
  GaugeBindings.bind(metricsRegistry, "ubaa.bykc.cache") { bykcService.cacheSize().toDouble() }
  GaugeBindings.bind(metricsRegistry, "ubaa.cgyy.cache") { cgyyService.cacheSize().toDouble() }
  GaugeBindings.bind(metricsRegistry, "ubaa.spoc.cache") { spocService.cacheSize().toDouble() }
  GaugeBindings.bind(metricsRegistry, "ubaa.ygdk.cache") { ygdkService.cacheSize().toDouble() }
  GaugeBindings.bind(metricsRegistry, "ubaa.ygdk.context.cache") {
    ygdkService.contextCacheSize().toDouble()
  }
}
