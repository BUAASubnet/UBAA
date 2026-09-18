package cn.edu.ubaa.ihome

import cn.edu.ubaa.api.feature.IhomeUpstreamClient
import cn.edu.ubaa.auth.GlobalSessionManager
import cn.edu.ubaa.auth.SessionManager
import cn.edu.ubaa.utils.VpnCipher
import java.util.concurrent.ConcurrentHashMap

/** token 和操作锁绑定到当前服务器会话，重新登录时不会复用旧账号状态。 */
internal class IhomeService(private val sessions: SessionManager = GlobalSessionManager.instance) {
  private data class Cached(
      val session: SessionManager.UserSession,
      val client: IhomeUpstreamClient,
      @Volatile var touched: Long,
  )

  private val clients = ConcurrentHashMap<String, Cached>()

  suspend fun client(username: String): IhomeUpstreamClient {
    val session = sessions.requireSession(username)
    return clients
        .compute(username) { _, old ->
          if (old?.session === session) old.also { it.touched = System.currentTimeMillis() }
          else {
            old?.client?.close()
            Cached(
                session,
                IhomeUpstreamClient(session.client, VpnCipher::toVpnUrl, VpnCipher::fromVpnUrl),
                System.currentTimeMillis(),
            )
          }
        }!!
        .client
  }

  fun cleanup() {
    val cutoff = System.currentTimeMillis() - 30 * 60 * 1000L
    clients.forEach { (key, value) ->
      if (value.touched < cutoff && clients.remove(key, value)) value.client.close()
    }
  }

  fun close() {
    clients.values.forEach { it.client.close() }
    clients.clear()
  }
}

internal object GlobalIhomeService {
  val instance by lazy { IhomeService() }
}
