package cn.edu.ubaa.auth

import io.ktor.client.HttpClient
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class AcademicPortalWarmupCoordinator(
    private val sessionManager: SessionManager = GlobalSessionManager.instance,
    private val portalProbe: suspend (HttpClient) -> AcademicPortalProbeResult =
        ByxtService::initializeSession,
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
) {
  @Volatile private var closed = false
  private val inflightProbes =
      ConcurrentHashMap<String, kotlinx.coroutines.Deferred<AcademicPortalProbeResult>>()

  fun warmup(username: String, client: HttpClient) {
    ensureProbe(username, client)
  }

  suspend fun awaitOrStart(username: String, client: HttpClient): AcademicPortalProbeResult {
    return ensureProbe(username, client).await()
  }

  fun clear(username: String) {
    inflightProbes.remove(username)?.cancel()
  }

  fun close() {
    if (closed) return
    closed = true
    inflightProbes.values.forEach { it.cancel() }
    inflightProbes.clear()
    scope.cancel()
  }

  fun isClosed(): Boolean = closed || !scope.isActive

  private fun ensureProbe(
      username: String,
      client: HttpClient,
  ): kotlinx.coroutines.Deferred<AcademicPortalProbeResult> {
    inflightProbes[username]?.let {
      return it
    }

    val deferred = scope.async(start = CoroutineStart.LAZY) { portalProbe(client) }
    val existing = inflightProbes.putIfAbsent(username, deferred)
    if (existing != null) {
      deferred.cancel()
      return existing
    }

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    fun handleCompletion(cause: Throwable?) {
      inflightProbes.remove(username, deferred)
      if (cause != null) return

      val result = runCatching { deferred.getCompleted() }.getOrNull() ?: return
      val portalType = result.portalType
      if (portalType == AcademicPortalType.UNKNOWN) return

      scope.launch { sessionManager.updateSessionPortalType(username, portalType) }
    }
    deferred.invokeOnCompletion(::handleCompletion)
    deferred.start()
    return deferred
  }
}

object GlobalAcademicPortalWarmupCoordinator {
  @Volatile private var current: AcademicPortalWarmupCoordinator? = null

  val instance: AcademicPortalWarmupCoordinator
    get() {
      current
          ?.takeUnless { it.isClosed() }
          ?.let {
            return it
          }
      return synchronized(this) {
        current?.takeUnless { it.isClosed() }
            ?: AcademicPortalWarmupCoordinator().also { current = it }
      }
    }

  fun clear(username: String) {
    current?.takeUnless { it.isClosed() }?.clear(username)
  }

  fun close() {
    synchronized(this) {
      current?.close()
      current = null
    }
  }
}
