package cn.edu.ubaa.judge

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

/** 注册希冀作业查询相关路由。 */
fun Route.judgeRouting() {
  val judgeService = GlobalJudgeService.instance

  route("/api/v1/judge") {
    get("/assignments") {
      val session = call.requireUserSession()
      call.observeBusinessOperation("judge", "list_assignments") {
        call.runJudgeCall(this) {
          call.respond(HttpStatusCode.OK, judgeService.getAssignments(session.username))
        }
      }
    }

    get("/courses/{courseId}/assignments/{assignmentId}") {
      val session = call.requireUserSession()
      val courseId =
          call.parameters["courseId"]?.takeIf { it.isNotBlank() }
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      val assignmentId =
          call.parameters["assignmentId"]?.takeIf { it.isNotBlank() }
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")

      call.observeBusinessOperation("judge", "get_assignment_detail") {
        call.runJudgeCall(this) {
          call.respond(
              HttpStatusCode.OK,
              judgeService.getAssignmentDetail(session.username, courseId, assignmentId),
          )
        }
      }
    }
  }
}

private suspend fun ApplicationCall.runJudgeCall(
    scope: BusinessOperationScope,
    block: suspend () -> Unit,
) {
  try {
    block()
  } catch (e: UpstreamTimeoutException) {
    scope.markTimeout()
    respondError(HttpStatusCode.GatewayTimeout, e.code, "希冀服务响应超时，请稍后重试")
  } catch (e: JudgeAuthenticationException) {
    scope.markUnauthenticated()
    respondError(HttpStatusCode.BadGateway, "judge_auth_failed")
  } catch (e: JudgeException) {
    scope.markBusinessFailure()
    respondError(HttpStatusCode.BadGateway, "judge_error")
  } catch (e: Exception) {
    scope.markError()
    respondError(HttpStatusCode.InternalServerError, "internal_server_error")
  }
}
