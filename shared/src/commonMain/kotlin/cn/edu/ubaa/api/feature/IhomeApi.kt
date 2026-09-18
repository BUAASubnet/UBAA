package cn.edu.ubaa.api.feature

import cn.edu.ubaa.api.ConnectionRuntime
import cn.edu.ubaa.api.auth.ApiClientProvider
import cn.edu.ubaa.api.auth.safeApiCall
import cn.edu.ubaa.api.core.ApiClient
import cn.edu.ubaa.model.dto.*
import io.ktor.client.request.*
import io.ktor.http.*

interface IhomeApiBackend {
  suspend fun getPage(query: IhomeQuery): Result<IhomePage>

  suspend fun getDetail(id: Long, mine: Boolean = false): Result<IhomeAppeal>

  suspend fun getConfig(): Result<IhomeConfig>

  suspend fun getNotices(): Result<List<IhomeNotice>>

  suspend fun getNotice(id: Long): Result<IhomeNotice>

  suspend fun setReaction(id: Long, request: IhomeReactionRequest): Result<IhomeReactionResult>
}

open class IhomeApi(
    private val backend: () -> IhomeApiBackend = { ConnectionRuntime.apiFactory().ihomeApi() }
) : IhomeApiBackend {
  override suspend fun getPage(query: IhomeQuery) = backend().getPage(query)

  override suspend fun getDetail(id: Long, mine: Boolean) = backend().getDetail(id, mine)

  override suspend fun getConfig() = backend().getConfig()

  override suspend fun getNotices() = backend().getNotices()

  override suspend fun getNotice(id: Long) = backend().getNotice(id)

  override suspend fun setReaction(id: Long, request: IhomeReactionRequest) =
      backend().setReaction(id, request)
}

internal class RelayIhomeApiBackend(private val client: ApiClient = ApiClientProvider.shared) :
    IhomeApiBackend {
  override suspend fun getPage(query: IhomeQuery): Result<IhomePage> = safeApiCall {
    client.getClient().get("api/v1/ihome/appeals") {
      parameter("scope", query.scope.name)
      parameter("page", query.page)
      parameter("limit", query.limit)
      parameter("keyword", query.keyword)
      parameter("filter", query.filter.name)
      query.categoryId?.let { parameter("categoryId", it) }
    }
  }

  override suspend fun getDetail(id: Long, mine: Boolean): Result<IhomeAppeal> = safeApiCall {
    client.getClient().get("api/v1/ihome/appeals/$id") { parameter("mine", mine) }
  }

  override suspend fun getConfig(): Result<IhomeConfig> = safeApiCall {
    client.getClient().get("api/v1/ihome/config")
  }

  override suspend fun getNotices(): Result<List<IhomeNotice>> = safeApiCall {
    client.getClient().get("api/v1/ihome/notices")
  }

  override suspend fun getNotice(id: Long): Result<IhomeNotice> = safeApiCall {
    client.getClient().get("api/v1/ihome/notices/$id")
  }

  override suspend fun setReaction(
      id: Long,
      request: IhomeReactionRequest,
  ): Result<IhomeReactionResult> = safeApiCall {
    client.getClient().post("api/v1/ihome/appeals/$id/reaction") {
      contentType(ContentType.Application.Json)
      setBody(request)
    }
  }
}
