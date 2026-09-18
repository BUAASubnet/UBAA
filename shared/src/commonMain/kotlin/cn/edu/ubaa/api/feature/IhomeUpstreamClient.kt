package cn.edu.ubaa.api.feature

import cn.edu.ubaa.model.dto.*
import io.ktor.client.HttpClient
import io.ktor.client.plugins.logging.*
import io.ktor.client.request.*
import io.ktor.client.statement.bodyAsText
import io.ktor.http.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonElement

/** 基于既有 CAS 会话的协议实现，直连、WebVPN 和中转共享解析与写操作语义。 */
class IhomeUpstreamClient(
    baseClient: HttpClient,
    private val route: (String) -> String = { it },
    private val unroute: (String) -> String = { it },
) {
  private val client =
      baseClient.config {
        followRedirects = false
        expectSuccess = false
        install(Logging) { level = LogLevel.NONE }
      }
  private val authMutex = Mutex()
  private val mutationMutex = Mutex()
  private var token: String? = null
  private var closed = false

  suspend fun getPage(query: IhomeQuery): IhomePage {
    require(query.page > 0 && query.limit in 1..100 && query.keyword.length <= 200) { "查询参数无效" }
    require(query.categoryId == null || query.categoryId > 0) { "分类无效" }
    val path =
        when (query.scope) {
          IhomeScope.PUBLIC -> "/appeal"
          IhomeScope.MINE -> "/appeal/my_appreal"
          IhomeScope.FOLLOWED -> "/appeal/my_follow"
          IhomeScope.APPRAISED -> "/appraise/my_appraise"
        }
    val parameters = buildList {
      add("limit" to query.limit.toString())
      add("page" to query.page.toString())
      if (query.scope == IhomeScope.PUBLIC) {
        if (query.keyword.isNotBlank()) add("keyword" to query.keyword.trim())
        query.categoryId?.let { add("sqlb_id" to it.toString()) }
      }
      if (query.scope in listOf(IhomeScope.PUBLIC, IhomeScope.MINE)) {
        when (query.filter) {
          IhomeFilter.ALL -> Unit
          IhomeFilter.NEWEST -> add("publish_time" to "1")
          IhomeFilter.OLDEST -> {
            require(query.scope == IhomeScope.PUBLIC) { "当前列表不支持此排序" }
            add("publish_time" to "0")
          }
          IhomeFilter.REPLY_TIME -> {
            require(query.scope == IhomeScope.MINE) { "当前列表不支持此排序" }
            add("reply_time" to "0")
          }
          IhomeFilter.REPLIED,
          IhomeFilter.UNREPLIED ->
              add(
                  (if (query.scope == IhomeScope.MINE) "is_reply" else "reply") to
                      (if (query.filter == IhomeFilter.REPLIED) "1" else "0")
              )
        }
      }
    }
    return IhomeProtocol.page(read(path, parameters), query.scope)
  }

  suspend fun getDetail(id: Long, mine: Boolean = false): IhomeAppeal {
    require(id > 0) { "诉求编号无效" }
    return IhomeProtocol.appeal(read(if (mine) "/appeal/my_appreal/$id" else "/appeal/$id"))
  }

  suspend fun getConfig(): IhomeConfig =
      IhomeProtocol.config(
          read("/general_set_more", listOf("key[]" to "fabulous", "key[]" to "fabulous_show")),
          read("/mobile/types", listOf("type_mark" to "SQLB")),
      )

  suspend fun getNotices(): List<IhomeNotice> = IhomeProtocol.notices(read("/notice"))

  suspend fun getNotice(id: Long): IhomeNotice {
    require(id > 0) { "公告编号无效" }
    return IhomeProtocol.notice(read("/notice", listOf("id" to id.toString())))
  }

  suspend fun setReaction(id: Long, request: IhomeReactionRequest): IhomeReactionResult =
      mutationMutex.withLock {
        val before = getDetail(id)
        if (before.enabled(request.reaction) == request.enabled)
            return@withLock IhomeReactionResult(before, true)
        if (request.reaction == IhomeReaction.SUPPORT && !getConfig().supportEnabled) {
          throw IhomeException("ihome_disabled", "平台当前未开放支持功能")
        }
        if (before.enabled(request.reaction) == null)
            throw IhomeException("ihome_protocol", "无法确认当前操作状态，请刷新后重试")
        var rejected = false
        try {
          // 上游是切换操作，只发送一次；中转重复请求先读取目标状态，避免再次反向切换。
          val path =
              if (request.reaction == IhomeReaction.FOLLOW) "/appeal_follow/$id"
              else "/appeal/appeal_praise/$id"
          val response =
              client.post(route("$BASE$path")) {
                header(HttpHeaders.Authorization, "Bearer ${ensureToken()}")
                if (request.reaction == IhomeReaction.FOLLOW) {
                  contentType(ContentType.Application.Json)
                  setBody("{}")
                }
              }
          if (response.status.value == 401) token = null
          if (response.status.value !in 200..299) rejected = true
          else IhomeProtocol.envelope(response.bodyAsText())
        } catch (e: CancellationException) {
          throw e
        } catch (_: Exception) {
          // 超时、协议变化或响应丢失均不重发，以下回查是唯一确认依据。
        }
        val after =
            try {
              getDetail(id)
            } catch (e: CancellationException) {
              throw e
            } catch (_: Exception) {
              null
            }
        val confirmed = after?.enabled(request.reaction) == request.enabled
        IhomeReactionResult(
            after,
            confirmed,
            when {
              confirmed -> ""
              rejected -> "操作未完成，请刷新确认当前状态"
              else -> "操作结果未确认，请刷新后再操作"
            },
        )
      }

  private fun IhomeAppeal.enabled(reaction: IhomeReaction) =
      if (reaction == IhomeReaction.FOLLOW) isFollowed else isSupported

  private suspend fun read(
      path: String,
      params: List<Pair<String, String>> = emptyList(),
  ): JsonElement {
    repeat(2) { attempt ->
      val credential = ensureToken()
      val url =
          URLBuilder("$BASE$path")
              .apply { params.forEach { (k, v) -> parameters.append(k, v) } }
              .buildString()
      val response =
          client.get(route(url)) { header(HttpHeaders.Authorization, "Bearer $credential") }
      if (response.status.value == 401 && attempt == 0) {
        if (token == credential) token = null
      } else {
        if (response.status.value == 401) throw IhomeException("ihome_auth", "ihome 登录已失效，请重新登录")
        if (response.status.value !in 200..299)
            throw IhomeException("ihome_upstream", "ihome 暂时不可用，请稍后重试")
        return IhomeProtocol.envelope(response.bodyAsText())
      }
    }
    throw IhomeException("ihome_auth", "ihome 登录已失效，请重新登录")
  }

  private suspend fun ensureToken(): String =
      authMutex.withLock {
        if (closed) throw IhomeException("ihome_auth", "会话已切换，请重新打开 ihome")
        token?.let {
          return@withLock it
        }
        var next =
            URLBuilder("https://sso.buaa.edu.cn/login")
                .apply { parameters.append("service", "http://i.buaa.edu.cn/api/authLogin") }
                .buildString()
        repeat(12) {
          val original = Url(unroute(next))
          if (
              original.host !in setOf("sso.buaa.edu.cn", "i.buaa.edu.cn") ||
                  original.protocol.name !in setOf("https", "http")
          ) {
            throw IhomeException("ihome_auth", "ihome 登录跳转异常")
          }
          if (original.host == "i.buaa.edu.cn" && original.encodedPath == "/web/") {
            val params = parseQueryString(original.fragment.substringAfter('?', ""))
            if (params["type"] == "0")
                params["token"]
                    ?.takeIf { it.isNotBlank() }
                    ?.let {
                      if (closed) throw IhomeException("ihome_auth", "会话已切换")
                      token = it
                      return@withLock it
                    }
          }
          // 抓包中的 ihome HTTP 回调被浏览器升级为 HTTPS；CAS service 参数仍保留原值。
          val secure =
              URLBuilder(original)
                  .apply {
                    protocol = URLProtocol.HTTPS
                    port = 443
                  }
                  .buildString()
          val response = client.get(route(secure))
          if (response.status.value in 500..599) {
            throw IhomeException("ihome_upstream", "iHome 登录服务暂时不可用，请稍后重试")
          }
          val location =
              response.headers[HttpHeaders.Location]
                  ?: throw IhomeException("ihome_auth", "无法复用统一认证登录，请重新登录 UBAA")
          next =
              URLBuilder(response.call.request.url)
                  .apply {
                    // takeFrom 会合并查询参数；每一跳必须移除前一跳的 service 或 ticket。
                    parameters.clear()
                    fragment = ""
                    takeFrom(location)
                  }
                  .buildString()
        }
        throw IhomeException("ihome_auth", "ihome 登录跳转次数过多")
      }

  fun close() {
    closed = true
    token = null
    client.close()
  }

  companion object {
    private const val BASE = "https://i.buaa.edu.cn/api"
  }
}
