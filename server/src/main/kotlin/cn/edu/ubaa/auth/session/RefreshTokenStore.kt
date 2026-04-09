package cn.edu.ubaa.auth

import cn.edu.ubaa.model.dto.LoginResponse
import cn.edu.ubaa.model.dto.TokenRefreshResponse
import cn.edu.ubaa.model.dto.UserData
import cn.edu.ubaa.utils.JwtUtil
import io.lettuce.core.api.async.RedisAsyncCommands
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Duration
import java.time.Instant
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.future.await
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class RefreshTokenRecord(
    val username: String,
    val tokenHash: String,
    val issuedAt: Instant,
    val expiresAt: Instant,
)

interface RefreshTokenStore {
  suspend fun saveToken(username: String, token: String, issuedAt: Instant, expiresAt: Instant)

  suspend fun findToken(token: String): RefreshTokenRecord?

  suspend fun rotateToken(
      username: String,
      oldToken: String,
      newToken: String,
      issuedAt: Instant,
      expiresAt: Instant,
  ): Boolean

  suspend fun deleteByUsername(username: String)

  fun close()
}

class RedisRefreshTokenStore(
    private val runtime: RedisRuntime = GlobalRedisRuntime.instance,
) : RefreshTokenStore {
  private val commands: RedisAsyncCommands<String, String>
    get() = runtime.asyncCommands
  private val mutexes = ConcurrentHashMap<String, Mutex>()

  override suspend fun saveToken(
      username: String,
      token: String,
      issuedAt: Instant,
      expiresAt: Instant,
  ) {
    withUserLock(username) {
      val existing = readRecord(username)
      existing?.let { deleteRecord(username, it.tokenHash) }

      val tokenHash = RefreshTokenUtil.hashToken(token)
      writeRecord(username, tokenHash, issuedAt, expiresAt)
    }
  }

  override suspend fun findToken(token: String): RefreshTokenRecord? {
    val tokenHash = RefreshTokenUtil.hashToken(token)
    val username = commands.get(indexKey(tokenHash)).await() ?: return null
    return withUserLock(username) {
      val record = readRecord(username) ?: return@withUserLock null
      if (record.tokenHash != tokenHash || record.expiresAt <= Instant.now()) {
        deleteRecord(username, record.tokenHash)
        return@withUserLock null
      }
      record
    }
  }

  override suspend fun rotateToken(
      username: String,
      oldToken: String,
      newToken: String,
      issuedAt: Instant,
      expiresAt: Instant,
  ): Boolean {
    return withUserLock(username) {
      val current = readRecord(username) ?: return@withUserLock false
      val oldHash = RefreshTokenUtil.hashToken(oldToken)
      if (current.tokenHash != oldHash || current.expiresAt <= Instant.now()) {
        deleteRecord(username, current.tokenHash)
        return@withUserLock false
      }

      deleteRecord(username, current.tokenHash)
      writeRecord(username, RefreshTokenUtil.hashToken(newToken), issuedAt, expiresAt)
      true
    }
  }

  override suspend fun deleteByUsername(username: String) {
    withUserLock(username) {
      val current = readRecord(username) ?: return@withUserLock
      deleteRecord(username, current.tokenHash)
    }
    mutexes.remove(username)
  }

  override fun close() {
    // No-op: Redis 连接由 GlobalRedisRuntime 统一管理
  }

  private suspend fun <T> withUserLock(username: String, block: suspend () -> T): T {
    val mutex = mutexes.computeIfAbsent(username) { Mutex() }
    return mutex.withLock { block() }
  }

  private suspend fun readRecord(username: String): RefreshTokenRecord? {
    val raw = commands.get(userKey(username)).await() ?: return null
    val parts = raw.split("|")
    if (parts.size != 3) {
      // Malformed record: remove user key and, if possible, the indexed token hash
      commands.del(userKey(username)).await()
      if (parts.isNotEmpty()) {
        commands.del(indexKey(parts[0])).await()
      }
      return null
    }
    val tokenHash = parts[0]
    val issuedAtMillis = parts[1].toLongOrNull()
    val expiresAtMillis = parts[2].toLongOrNull()
    if (issuedAtMillis == null || expiresAtMillis == null) {
      // Malformed timestamps: clean up associated keys
      commands.del(userKey(username)).await()
      commands.del(indexKey(tokenHash)).await()
      return null
    }
    val issuedAt = Instant.ofEpochMilli(issuedAtMillis)
    val expiresAt = Instant.ofEpochMilli(expiresAtMillis)
    return RefreshTokenRecord(username, tokenHash, issuedAt, expiresAt)
  }

  private suspend fun writeRecord(
      username: String,
      tokenHash: String,
      issuedAt: Instant,
      expiresAt: Instant,
  ) {
    val ttlSeconds = ttlSecondsUntil(expiresAt)
    commands
        .set(
            userKey(username),
            listOf(tokenHash, issuedAt.toEpochMilli(), expiresAt.toEpochMilli()).joinToString("|"),
        )
        .await()
    commands.expire(userKey(username), ttlSeconds).await()
    commands.set(indexKey(tokenHash), username).await()
    commands.expire(indexKey(tokenHash), ttlSeconds).await()
  }

  private suspend fun deleteRecord(username: String, tokenHash: String) {
    commands.del(userKey(username)).await()
    commands.del(indexKey(tokenHash)).await()
  }

  private fun ttlSecondsUntil(expiresAt: Instant): Long {
    val ttl = Duration.between(Instant.now(), expiresAt).seconds
    return ttl.coerceAtLeast(1L)
  }

  private fun userKey(username: String): String = "refresh:user:$username"

  private fun indexKey(tokenHash: String): String = "refresh:index:$tokenHash"
}

class RefreshTokenService(
    private val accessTokenTtl: Duration = AuthConfig.accessTokenTtl,
    private val refreshTokenTtl: Duration = AuthConfig.refreshTokenTtl,
    private val refreshTokenStore: RefreshTokenStore = RedisRefreshTokenStore(),
) {

  suspend fun issueLoginTokens(userData: UserData, username: String): LoginResponse {
    val refreshed = issueTokens(username)
    return LoginResponse(
        user = userData,
        accessToken = refreshed.accessToken,
        refreshToken = refreshed.refreshToken,
        accessTokenExpiresAt = refreshed.accessTokenExpiresAt,
        refreshTokenExpiresAt = refreshed.refreshTokenExpiresAt,
    )
  }

  suspend fun issueTokens(username: String): TokenRefreshResponse {
    val now = Instant.now()
    val accessTokenExpiresAt = now.plus(accessTokenTtl)
    val refreshTokenExpiresAt = now.plus(refreshTokenTtl)
    val refreshToken = RefreshTokenUtil.generateToken()

    refreshTokenStore.saveToken(username, refreshToken, now, refreshTokenExpiresAt)

    return TokenRefreshResponse(
        accessToken = JwtUtil.generateToken(username, accessTokenTtl),
        refreshToken = refreshToken,
        accessTokenExpiresAt = accessTokenExpiresAt.toString(),
        refreshTokenExpiresAt = refreshTokenExpiresAt.toString(),
    )
  }

  suspend fun refreshTokens(
      refreshToken: String,
      sessionManager: SessionManager,
  ): TokenRefreshResponse? {
    val current = refreshTokenStore.findToken(refreshToken) ?: return null
    val session =
        sessionManager.getSession(current.username, SessionManager.SessionAccess.TOUCH)
            ?: run {
              refreshTokenStore.deleteByUsername(current.username)
              return null
            }

    val now = Instant.now()
    val accessTokenExpiresAt = now.plus(accessTokenTtl)
    val refreshTokenExpiresAt = now.plus(refreshTokenTtl)
    val newRefreshToken = RefreshTokenUtil.generateToken()
    val rotated =
        refreshTokenStore.rotateToken(
            username = session.username,
            oldToken = refreshToken,
            newToken = newRefreshToken,
            issuedAt = now,
            expiresAt = refreshTokenExpiresAt,
        )
    if (!rotated) return null

    return TokenRefreshResponse(
        accessToken = JwtUtil.generateToken(session.username, accessTokenTtl),
        refreshToken = newRefreshToken,
        accessTokenExpiresAt = accessTokenExpiresAt.toString(),
        refreshTokenExpiresAt = refreshTokenExpiresAt.toString(),
    )
  }

  suspend fun invalidate(username: String) {
    refreshTokenStore.deleteByUsername(username)
  }

  fun close() {
    refreshTokenStore.close()
  }
}

object GlobalRefreshTokenService {
  @Volatile private var current: RefreshTokenService? = null

  val instance: RefreshTokenService
    get() {
      current?.let { return it }
      return synchronized(this) { current ?: RefreshTokenService().also { current = it } }
    }

  fun close() {
    synchronized(this) {
      current?.close()
      current = null
    }
  }
}

private object RefreshTokenUtil {
  private val secureRandom = SecureRandom()

  fun generateToken(): String {
    val bytes = ByteArray(32)
    secureRandom.nextBytes(bytes)
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
  }

  fun hashToken(token: String): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(token.toByteArray())
    return digest.joinToString("") { "%02x".format(it) }
  }
}
