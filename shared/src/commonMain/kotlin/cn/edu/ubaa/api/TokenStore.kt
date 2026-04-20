package cn.edu.ubaa.api

import com.russhwolf.settings.Settings
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

data class StoredAuthTokens(
    val accessToken: String,
    val refreshToken: String,
    val accessTokenExpiresAt: String? = null,
    val refreshTokenExpiresAt: String? = null,
)

/** Simple multiplatform auth token store backed by persistent Settings. */
object AuthTokensStore {
  private const val KEY_ACCESS_TOKEN = "auth_access_token"
  private const val KEY_REFRESH_TOKEN = "auth_refresh_token"
  private const val KEY_ACCESS_TOKEN_EXPIRES_AT = "auth_access_token_expires_at"
  private const val KEY_REFRESH_TOKEN_EXPIRES_AT = "auth_refresh_token_expires_at"
  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun save(tokens: StoredAuthTokens) {
    settings.putString(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN), tokens.accessToken)
    settings.putString(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN), tokens.refreshToken)
    tokens.accessTokenExpiresAt?.let {
      settings.putString(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN_EXPIRES_AT), it)
    } ?: settings.remove(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN_EXPIRES_AT))
    tokens.refreshTokenExpiresAt?.let {
      settings.putString(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN_EXPIRES_AT), it)
    } ?: settings.remove(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN_EXPIRES_AT))
  }

  fun get(): StoredAuthTokens? {
    val accessToken =
        settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN))
            ?: legacyValue(KEY_ACCESS_TOKEN)
            ?: return null
    val refreshToken =
        settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN))
            ?: legacyValue(KEY_REFRESH_TOKEN)
            ?: return null
    return StoredAuthTokens(
        accessToken = accessToken,
        refreshToken = refreshToken,
        accessTokenExpiresAt =
            settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN_EXPIRES_AT))
                ?: legacyValue(KEY_ACCESS_TOKEN_EXPIRES_AT),
        refreshTokenExpiresAt =
            settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN_EXPIRES_AT))
                ?: legacyValue(KEY_REFRESH_TOKEN_EXPIRES_AT),
    )
  }

  fun getAccessToken(): String? = get()?.accessToken

  fun clear() {
    settings.remove(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN))
    settings.remove(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN))
    settings.remove(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN_EXPIRES_AT))
    settings.remove(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN_EXPIRES_AT))
    if (
        ConnectionModeStore.get() == null ||
            ConnectionModeStore.get() == ConnectionMode.SERVER_RELAY
    ) {
      settings.remove(ModeScopedSessionStore.legacyKey(KEY_ACCESS_TOKEN))
      settings.remove(ModeScopedSessionStore.legacyKey(KEY_REFRESH_TOKEN))
      settings.remove(ModeScopedSessionStore.legacyKey(KEY_ACCESS_TOKEN_EXPIRES_AT))
      settings.remove(ModeScopedSessionStore.legacyKey(KEY_REFRESH_TOKEN_EXPIRES_AT))
    }
  }

  fun clearAllScopes() {
    ConnectionMode.entries.forEach { mode ->
      settings.remove(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN, mode))
      settings.remove(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN, mode))
      settings.remove(ModeScopedSessionStore.scopedKey(KEY_ACCESS_TOKEN_EXPIRES_AT, mode))
      settings.remove(ModeScopedSessionStore.scopedKey(KEY_REFRESH_TOKEN_EXPIRES_AT, mode))
    }
    settings.remove(ModeScopedSessionStore.legacyKey(KEY_ACCESS_TOKEN))
    settings.remove(ModeScopedSessionStore.legacyKey(KEY_REFRESH_TOKEN))
    settings.remove(ModeScopedSessionStore.legacyKey(KEY_ACCESS_TOKEN_EXPIRES_AT))
    settings.remove(ModeScopedSessionStore.legacyKey(KEY_REFRESH_TOKEN_EXPIRES_AT))
  }

  private fun legacyValue(key: String): String? =
      if (
          ConnectionModeStore.get() == null ||
              ConnectionModeStore.get() == ConnectionMode.SERVER_RELAY
      ) {
        settings.getStringOrNull(ModeScopedSessionStore.legacyKey(key))
      } else {
        null
      }
}

/** 客户端标识存储：用于关联预登录会话 */
object ClientIdStore {
  private const val KEY_CLIENT_ID = "client_id"
  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  /** 获取或创建 clientId */
  @OptIn(ExperimentalUuidApi::class)
  fun getOrCreate(): String {
    return settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_CLIENT_ID))
        ?: legacyValue()
        ?: run {
          val newId = Uuid.random().toString()
          settings.putString(ModeScopedSessionStore.scopedKey(KEY_CLIENT_ID), newId)
          newId
        }
  }

  /** 获取 clientId（可能为 null） */
  fun get(): String? =
      settings.getStringOrNull(ModeScopedSessionStore.scopedKey(KEY_CLIENT_ID)) ?: legacyValue()

  /** 清除 clientId（通常不需要，除非要完全重置客户端） */
  fun clear() {
    settings.remove(ModeScopedSessionStore.scopedKey(KEY_CLIENT_ID))
    if (
        ConnectionModeStore.get() == null ||
            ConnectionModeStore.get() == ConnectionMode.SERVER_RELAY
    ) {
      settings.remove(ModeScopedSessionStore.legacyKey(KEY_CLIENT_ID))
    }
  }

  fun clearAllScopes() {
    ConnectionMode.entries.forEach { mode ->
      settings.remove(ModeScopedSessionStore.scopedKey(KEY_CLIENT_ID, mode))
    }
    settings.remove(ModeScopedSessionStore.legacyKey(KEY_CLIENT_ID))
  }

  private fun legacyValue(): String? =
      if (
          ConnectionModeStore.get() == null ||
              ConnectionModeStore.get() == ConnectionMode.SERVER_RELAY
      ) {
        settings.getStringOrNull(ModeScopedSessionStore.legacyKey(KEY_CLIENT_ID))
      } else {
        null
      }
}
