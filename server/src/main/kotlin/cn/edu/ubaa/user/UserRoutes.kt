package cn.edu.ubaa.user

import cn.edu.ubaa.auth.ErrorDetails
import cn.edu.ubaa.auth.ErrorResponse
import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.LoginException
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
      try {
        val userInfo = userService.fetchUserInfo(username)
        call.respond(HttpStatusCode.OK, userInfo)
      } catch (e: Exception) {
        val status =
          if (e is LoginException) HttpStatusCode.Unauthorized else HttpStatusCode.BadGateway
        call.respond(status, ErrorResponse(ErrorDetails("error", e.message ?: "Error")))
      }
    }
  }
}
