package cn.edu.ubaa.ihome

import cn.edu.ubaa.api.feature.IhomeException
import cn.edu.ubaa.api.feature.IhomeUpstreamClient
import cn.edu.ubaa.auth.JwtAuth.requireUserSession
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.model.dto.*
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.*
import kotlinx.coroutines.CancellationException

fun Route.ihomeRouting() {
  route("/api/v1/ihome") {
    get("/appeals") {
      call.ihomeCall {
        val p = call.request.queryParameters
        val query =
            IhomeQuery(
                scope = p["scope"]?.let(IhomeScope::valueOf) ?: IhomeScope.PUBLIC,
                page = p["page"]?.toInt() ?: 1,
                limit = p["limit"]?.toInt() ?: 15,
                keyword = p["keyword"].orEmpty(),
                filter = p["filter"]?.let(IhomeFilter::valueOf) ?: IhomeFilter.ALL,
                categoryId = p["categoryId"]?.toLong(),
            )
        call.respond(getPage(query))
      }
    }
    get("/appeals/{id}") {
      call.ihomeCall {
        call.respond(getDetail(call.ihomeId(), call.request.queryParameters["mine"] == "true"))
      }
    }
    get("/config") { call.ihomeCall { call.respond(getConfig()) } }
    get("/notices") { call.ihomeCall { call.respond(getNotices()) } }
    get("/notices/{id}") { call.ihomeCall { call.respond(getNotice(call.ihomeId())) } }
    post("/appeals/{id}/reaction") {
      call.ihomeCall {
        call.respond(setReaction(call.ihomeId(), call.receive<IhomeReactionRequest>()))
      }
    }
  }
}

private fun ApplicationCall.ihomeId() =
    parameters["id"]?.toLong()?.takeIf { it > 0 } ?: throw IllegalArgumentException("编号无效")

private suspend fun ApplicationCall.ihomeCall(block: suspend IhomeUpstreamClient.() -> Unit) {
  val session = requireUserSession()
  try {
    GlobalIhomeService.instance.client(session.username).block()
  } catch (e: CancellationException) {
    throw e
  } catch (_: IllegalArgumentException) {
    respondError(HttpStatusCode.BadRequest, "invalid_request")
  } catch (e: IhomeException) {
    respondError(HttpStatusCode.BadGateway, e.code, e.message)
  } catch (_: Exception) {
    respondError(HttpStatusCode.BadGateway, "ihome_error", "ihome 请求失败，请刷新确认当前状态")
  }
}
