package cn.edu.ubaa.api.local

import cn.edu.ubaa.api.ConnectionMode
import cn.edu.ubaa.api.ConnectionRuntime
import cn.edu.ubaa.api.auth.ApiCallException
import cn.edu.ubaa.api.feature.*
import cn.edu.ubaa.model.dto.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal class LocalIhomeApiBackend : IhomeApiBackend {
  private val mutex = Mutex()
  private var cachedKey: Triple<String, String, ConnectionMode>? = null
  private var cached: IhomeUpstreamClient? = null

  fun clearCache() {
    cached?.close()
    cached = null
    cachedKey = null
  }

  private suspend fun current(): IhomeUpstreamClient =
      mutex.withLock {
        val session = LocalAuthSessionStore.get() ?: throw localUnauthenticatedApiException()
        val mode = ConnectionRuntime.currentMode() ?: throw localUnauthenticatedApiException()
        val key = Triple(session.username, session.authenticatedAt, mode)
        if (key != cachedKey) {
          clearCache()
          cached =
              IhomeUpstreamClient(
                  LocalUpstreamClientProvider.shared(),
                  route = {
                    if (mode == ConnectionMode.WEBVPN) LocalWebVpnSupport.toWebVpnUrl(it) else it
                  },
                  unroute = LocalWebVpnSupport::fromWebVpnUrl,
              )
          cachedKey = key
        }
        cached!!
      }

  private suspend fun <T> call(block: suspend IhomeUpstreamClient.() -> T): Result<T> =
      try {
        Result.success(current().block())
      } catch (e: CancellationException) {
        throw e
      } catch (e: IhomeException) {
        Result.failure(ApiCallException(e.message ?: "ihome 请求失败", code = e.code))
      } catch (_: Exception) {
        Result.failure(ApiCallException("ihome 连接失败，请刷新后重试", code = "ihome_error"))
      }

  override suspend fun getPage(query: IhomeQuery) = call { getPage(query) }

  override suspend fun getDetail(id: Long, mine: Boolean) = call { getDetail(id, mine) }

  override suspend fun getConfig() = call { getConfig() }

  override suspend fun getNotices() = call { getNotices() }

  override suspend fun getNotice(id: Long) = call { getNotice(id) }

  override suspend fun setReaction(id: Long, request: IhomeReactionRequest) = call {
    setReaction(id, request)
  }
}
