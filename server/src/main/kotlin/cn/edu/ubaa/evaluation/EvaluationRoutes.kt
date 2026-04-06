package cn.edu.ubaa.evaluation

import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.observeBusinessOperation
import cn.edu.ubaa.model.evaluation.EvaluationCourse
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.plugins.ContentTransformationException
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import org.slf4j.LoggerFactory

private val log = LoggerFactory.getLogger("EvaluationRoutes")

/** 注册自动评教相关路由。 定义了客户端与服务端交互的 API 接口，用于获取评教列表和提交评教任务。 */
fun Route.evaluationRouting() {
  val evaluationService = GlobalEvaluationService.instance

  route("/api/v1/evaluation") {

    /** GET /api/v1/evaluation/list 获取所有评教课程列表（包括已评教和未评教），附带进度信息。 需要 JWT 认证。 */
    get("/list") {
      val username =
          call.jwtUsername
              ?: return@get call.respondError(HttpStatusCode.Unauthorized, "invalid_token")
      call.observeBusinessOperation("evaluation", "list") {
        try {
          val response = evaluationService.getAllCourses(username)
          call.respond(HttpStatusCode.OK, response)
        } catch (e: UpstreamTimeoutException) {
          markTimeout()
          call.respondError(HttpStatusCode.GatewayTimeout, e.code, "评教服务响应超时，请稍后重试")
        } catch (e: Exception) {
          markError()
          log.error("Failed to fetch evaluation list for $username", e)
          call.respondError(HttpStatusCode.InternalServerError, "evaluation_error")
        }
      }
    }

    /** POST /api/v1/evaluation/submit 提交评教任务。 接收 EvaluationCourse 列表，执行自动评教并返回结果。 需要 JWT 认证。 */
    post("/submit") {
      val username =
          call.jwtUsername
              ?: return@post call.respondError(HttpStatusCode.Unauthorized, "invalid_token")
      call.observeBusinessOperation("evaluation", "submit") {
        try {
          val coursesToEvaluate = call.receive<List<EvaluationCourse>>()
          if (coursesToEvaluate.isEmpty()) {
            markBusinessFailure()
            return@observeBusinessOperation call.respondError(
                HttpStatusCode.BadRequest,
                "invalid_request",
            )
          }

          val results = evaluationService.autoEvaluate(username, coursesToEvaluate)
          call.respond(HttpStatusCode.OK, results)
        } catch (e: ContentTransformationException) {
          markBusinessFailure()
          call.respondError(HttpStatusCode.BadRequest, "invalid_request")
        } catch (e: Exception) {
          markError()
          log.error("Failed to submit evaluations for $username", e)
          call.respondError(HttpStatusCode.InternalServerError, "evaluation_error")
        }
      }
    }
  }
}
