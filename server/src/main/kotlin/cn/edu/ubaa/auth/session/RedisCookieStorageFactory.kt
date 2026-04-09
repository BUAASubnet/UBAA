package cn.edu.ubaa.auth

import io.lettuce.core.api.async.RedisAsyncCommands
import kotlinx.coroutines.future.await

/** 管理共享 Redis 连接的 Cookie 存储工厂。 所有 [RedisCookieStorage] 实例共用同一个 Redis 连接，避免为每个用户创建独立连接导致资源泄漏。 */
class RedisCookieStorageFactory(
    private val runtime: RedisRuntime = GlobalRedisRuntime.instance,
) : ManagedCookieStorageFactory {
  private val commands: RedisAsyncCommands<String, String>
    get() = runtime.asyncCommands

  override fun create(subject: String, ttl: java.time.Duration): ManagedCookieStorage =
      RedisCookieStorage(commands, subject, ttl)

  override suspend fun clearSubject(subject: String) {
    commands.del(RedisCookieStorage.storageKey(subject)).await()
  }

  override fun close() = Unit
}
