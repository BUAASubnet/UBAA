package cn.edu.ubaa.version

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/** 注册应用版本检查相关路由。 */
fun Route.appVersionRouting(appVersionService: AppVersionService) {
  route("/api/v1/app") {
    /** GET /api/v1/app/version 查询客户端与服务端版本是否对齐。 */
    get("/version") {
      val clientVersion =
          call.request.queryParameters["clientVersion"]
              ?: return@get call.respond(
                  HttpStatusCode.BadRequest,
                  ErrorResponse(
                      ErrorDetails(
                          code = "missing_client_version",
                          message = "Missing required query parameter: clientVersion",
                      )
                  ),
              )

      call.respond(HttpStatusCode.OK, appVersionService.checkVersion(clientVersion))
    }
  }
}
