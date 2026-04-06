package cn.edu.ubaa.user

import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/** 注册用户信息相关路由。 */
fun Route.userRouting() {
  val userService = UserService()

  route("/api/v1/user") {
    /** GET /api/v1/user/info 获取当前登录用户的详细考籍与个人信息。 */
    get("/info") {
      val username = call.jwtUsername!!
      call.observeBusinessOperation("user", "user_info") {
        try {
          val userInfo = userService.fetchUserInfo(username)
          call.respond(HttpStatusCode.OK, userInfo)
        } catch (e: Exception) {
          if (e is LoginException) {
            markUnauthenticated()
          } else {
            markError()
          }
          val status =
              if (e is LoginException) HttpStatusCode.Unauthorized else HttpStatusCode.BadGateway
          val code = if (e is LoginException) "invalid_token" else "user_info_failed"
          call.respondError(status, code)
        }
      }
    }
  }
}
