package cn.edu.ubaa.cgyy

import cn.edu.ubaa.auth.JwtAuth.jwtUsername
import cn.edu.ubaa.auth.respondError
import cn.edu.ubaa.metrics.BusinessOperationScope
import cn.edu.ubaa.metrics.observeBusinessOperation
import cn.edu.ubaa.model.dto.CgyyReservationSubmitRequest
import cn.edu.ubaa.utils.UpstreamTimeoutException
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.call
import io.ktor.server.request.receive
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route

fun Route.cgyyRouting() {
  val cgyyService = GlobalCgyyService.instance

  route("/api/v1/cgyy") {
    get("/sites") {
      val username = call.jwtUsername!!
      call.observeBusinessOperation("cgyy", "list_sites") {
        try {
          call.respond(HttpStatusCode.OK, cgyyService.getVenueSites(username))
        } catch (e: UpstreamTimeoutException) {
          call.respondUpstreamTimeout(e, this)
        } catch (e: CgyyException) {
          call.respondCgyyError(e, this)
        }
      }
    }

    get("/purpose-types") {
      val username = call.jwtUsername!!
      call.observeBusinessOperation("cgyy", "list_purpose_types") {
        try {
          call.respond(HttpStatusCode.OK, cgyyService.getPurposeTypes(username))
        } catch (e: UpstreamTimeoutException) {
          call.respondUpstreamTimeout(e, this)
        } catch (e: CgyyException) {
          call.respondCgyyError(e, this)
        }
      }
    }

    get("/day-info") {
      val username = call.jwtUsername!!
      val venueSiteId =
          call.request.queryParameters["venueSiteId"]?.toIntOrNull()
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      val date =
          call.request.queryParameters["date"]
              ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
      call.observeBusinessOperation("cgyy", "get_day_info") {
        try {
          call.respond(HttpStatusCode.OK, cgyyService.getDayInfo(username, venueSiteId, date))
        } catch (e: UpstreamTimeoutException) {
          call.respondUpstreamTimeout(e, this)
        } catch (e: CgyyException) {
          call.respondCgyyError(e, this)
        }
      }
    }

    post("/reservations") {
      val username = call.jwtUsername!!
      val request =
          try {
            call.receive<CgyyReservationSubmitRequest>()
          } catch (_: Exception) {
            return@post call.respondError(HttpStatusCode.BadRequest, "invalid_request")
          }
      call.observeBusinessOperation("cgyy", "submit_reservation") {
        try {
          call.respond(HttpStatusCode.OK, cgyyService.submitReservation(username, request))
        } catch (e: UpstreamTimeoutException) {
          call.respondUpstreamTimeout(e, this)
        } catch (e: CgyyException) {
          call.respondCgyyError(e, this)
        }
      }
    }

    route("/orders") {
      get("/lock-code") {
        val username = call.jwtUsername!!
        call.observeBusinessOperation("cgyy", "get_lock_code") {
          try {
            call.respond(HttpStatusCode.OK, cgyyService.getLockCode(username))
          } catch (e: UpstreamTimeoutException) {
            call.respondUpstreamTimeout(e, this)
          } catch (e: CgyyException) {
            call.respondCgyyError(e, this)
          }
        }
      }

      get {
        val username = call.jwtUsername!!
        val page = call.request.queryParameters["page"]?.toIntOrNull() ?: 0
        val size = call.request.queryParameters["size"]?.toIntOrNull() ?: 20
        call.observeBusinessOperation("cgyy", "list_orders") {
          try {
            call.respond(HttpStatusCode.OK, cgyyService.getOrders(username, page, size))
          } catch (e: UpstreamTimeoutException) {
            call.respondUpstreamTimeout(e, this)
          } catch (e: CgyyException) {
            call.respondCgyyError(e, this)
          }
        }
      }

      get("/{orderId}") {
        val username = call.jwtUsername!!
        val orderId =
            call.parameters["orderId"]?.toIntOrNull()
                ?: return@get call.respondError(HttpStatusCode.BadRequest, "invalid_request")
        call.observeBusinessOperation("cgyy", "get_order_detail") {
          try {
            call.respond(HttpStatusCode.OK, cgyyService.getOrderDetail(username, orderId))
          } catch (e: UpstreamTimeoutException) {
            call.respondUpstreamTimeout(e, this)
          } catch (e: CgyyException) {
            call.respondCgyyError(e, this)
          }
        }
      }

      post("/{orderId}/cancel") {
        val username = call.jwtUsername!!
        val orderId =
            call.parameters["orderId"]?.toIntOrNull()
                ?: return@post call.respondError(HttpStatusCode.BadRequest, "invalid_request")
        call.observeBusinessOperation("cgyy", "cancel_order") {
          try {
            call.respond(HttpStatusCode.OK, cgyyService.cancelOrder(username, orderId))
          } catch (e: UpstreamTimeoutException) {
            call.respondUpstreamTimeout(e, this)
          } catch (e: CgyyException) {
            call.respondCgyyError(e, this)
          }
        }
      }
    }
  }
}

private suspend fun ApplicationCall.respondCgyyError(
    e: CgyyException,
    scope: BusinessOperationScope? = null,
) {
  val status =
      when (e.code) {
        "invalid_request",
        "reservation_invalid",
        "reservation_token_missing" -> HttpStatusCode.BadRequest
        "unauthenticated" -> HttpStatusCode.Unauthorized
        "captcha_error" -> HttpStatusCode.BadGateway
        else -> HttpStatusCode.BadGateway
      }
  when (e.code) {
    "invalid_request",
    "reservation_invalid",
    "reservation_token_missing" -> scope?.markBusinessFailure()
    "unauthenticated" -> scope?.markUnauthenticated()
    else -> scope?.markError()
  }
  respondError(status, e.code)
}

private suspend fun ApplicationCall.respondUpstreamTimeout(
    e: UpstreamTimeoutException,
    scope: BusinessOperationScope? = null,
) {
  scope?.markTimeout()
  respondError(HttpStatusCode.GatewayTimeout, e.code)
}
