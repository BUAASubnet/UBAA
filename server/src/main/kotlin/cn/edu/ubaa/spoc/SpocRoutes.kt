package cn.edu.ubaa.spoc

import cn.edu.ubaa.auth.JwtAuth.requireUserSession
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.BusinessOperationScope
import cn.edu.ubaa.metrics.observeBusinessOperation
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/** 注册 SPOC 作业查询相关路由。 */
fun Route.spocRouting() {
  val spocService = GlobalSpocService.instance

  route("/api/v1/spoc") {
    get("/assignments") {
      val session = call.requireUserSession()
      call.observeBusinessOperation("spoc", "list_assignments") {
        call.runSpocCall(this) {
          call.respond(HttpStatusCode.OK, spocService.getAssignments(session.username))
        }
      }
    }

    get("/assignments/{assignmentId}") {
      val session = call.requireUserSession()
      val assignmentId =
          call.parameters["assignmentId"]?.takeIf { it.isNotBlank() }
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")

      call.observeBusinessOperation("spoc", "get_assignment_detail") {
        call.runSpocCall(this) {
          call.respond(
              HttpStatusCode.OK,
              spocService.getAssignmentDetail(session.username, assignmentId),
          )
        }
      }
    }
  }
}

private suspend fun ApplicationCall.runSpocCall(
    scope: BusinessOperationScope,
    block: suspend () -> Unit,
) {
  try {
    block()
  } catch (e: UpstreamTimeoutException) {
    scope.markTimeout()
    respondError(HttpStatusCode.GatewayTimeout, e.code, "SPOC 服务响应超时，请稍后重试")
  } catch (e: SpocAuthenticationException) {
    scope.markUnauthenticated()
    respondError(HttpStatusCode.BadGateway, "spoc_auth_failed")
  } catch (e: SpocException) {
    scope.markBusinessFailure()
    respondError(HttpStatusCode.BadGateway, "spoc_error")
  } catch (e: Exception) {
    scope.markError()
    respondError(HttpStatusCode.InternalServerError, "internal_server_error")
  }
}
