package cn.edu.ubaa.version

import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/** 注册应用版本检查相关路由。 */
fun Route.appVersionRouting(appVersionService: AppVersionService) {
  route("/api/v1/app") {
    /** GET /api/v1/app/version 查询当前客户端是否有新版本。 */
    get("/version") {
      call.observeBusinessOperation("app_version", "check") {
        val clientVersion =
            call.request.queryParameters["clientVersion"]
                ?: run {
                  markBusinessFailure()
                  return@observeBusinessOperation call.respondError(
                      HttpStatusCode.BadRequest,
                      "missing_client_version",
                  )
                }

        call.respond(HttpStatusCode.OK, appVersionService.checkVersion(clientVersion))
      }
    }
  }
}
