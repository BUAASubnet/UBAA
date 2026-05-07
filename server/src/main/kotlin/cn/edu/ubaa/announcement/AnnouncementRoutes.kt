package cn.edu.ubaa.announcement

import cn.edu.ubaa.metrics.observeBusinessOperation
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.call
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.route

/** 注册应用公告相关路由。 */
fun Route.appAnnouncementRouting(announcementProvider: AnnouncementProvider) {
  route("/api/v1/app") {
    /** GET /api/v1/app/announcement 查询当前应展示的公告。 */
    get("/announcement") {
      call.observeBusinessOperation("app_announcement", "check") {
        val announcement = announcementProvider.currentAnnouncement()
        if (announcement == null) {
          call.respond(HttpStatusCode.NoContent)
        } else {
          call.respond(HttpStatusCode.OK, announcement)
        }
      }
    }
  }
}
