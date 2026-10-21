package cn.edu.ubaa.api

import cn.edu.ubaa.api.auth.ApiClientProvider
import cn.edu.ubaa.api.core.ApiFactory
import cn.edu.ubaa.api.core.DefaultApiFactory
import cn.edu.ubaa.api.local.LocalAuthSessionStore
import cn.edu.ubaa.api.local.LocalCookieStore
import cn.edu.ubaa.api.local.LocalJudgeApiCache
import cn.edu.ubaa.api.local.LocalUpstreamClientProvider
import cn.edu.ubaa.api.storage.AuthTokensStore
import cn.edu.ubaa.api.storage.ClientIdStore
import cn.edu.ubaa.api.storage.CredentialStore
import cn.edu.ubaa.api.storage.GradeScoreCacheStore
import cn.edu.ubaa.repository.GlobalTermRepository
import cn.edu.ubaa.supportsLocalConnectionModes
import com.russhwolf.settings.Settings
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class ConnectionMode(
    val storageKey: String,
    val displayName: String,
    val description: String,
) {
  DIRECT(
      storageKey = "direct",
      displayName = "直连模式",
      description = "直接访问校内上游。",
  ),
  WEBVPN(
      storageKey = "webvpn",
      displayName = "WebVPN模式",
      description = "通过北航 WebVPN 访问上游。",
  ),
  SERVER_RELAY(
      storageKey = "server_relay",
      displayName = "服务器中转模式",
      description = "使用 UBAA 服务端代理访问。",
  );

  companion object {
    fun fromStorageKey(value: String?): ConnectionMode? =
        entries.firstOrNull { it.storageKey == value?.trim()?.lowercase() }
  }
}

object ConnectionModeStore {
  private const val KEY_CONNECTION_MODE = "connection_mode"
  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun save(mode: ConnectionMode) {
    settings.putString(KEY_CONNECTION_MODE, mode.storageKey)
  }

  fun get(): ConnectionMode? =
      ConnectionMode.fromStorageKey(settings.getStringOrNull(KEY_CONNECTION_MODE))

  fun clear() {
    settings.remove(KEY_CONNECTION_MODE)
  }
}

object ConnectionRuntime {
  internal var apiFactoryProvider: () -> ApiFactory = { DefaultApiFactory }

  private val _currentMode = MutableStateFlow<ConnectionMode?>(null)
  val currentModeFlow: StateFlow<ConnectionMode?> = _currentMode.asStateFlow()

  internal fun apiFactory(): ApiFactory = apiFactoryProvider()

  fun availableModes(): List<ConnectionMode> =
      if (supportsLocalConnectionModes()) {
        listOf(ConnectionMode.DIRECT, ConnectionMode.WEBVPN)
      } else {
        emptyList()
      }

  fun resolveSelectedMode(): ConnectionMode? {
    val allowedModes = availableModes()
    val storedMode = ConnectionModeStore.get()
    // 已弃用的中转配置不能恢复认证或触发自动登录，返回连接方式选择页。
    if (storedMode != null && storedMode !in allowedModes) {
      resetSession()
      ConnectionModeStore.clear()
    }
    val resolvedMode =
        when {
          storedMode != null && storedMode in allowedModes -> storedMode
          allowedModes.size == 1 -> allowedModes.single().also(ConnectionModeStore::save)
          else -> null
        }
    _currentMode.value = resolvedMode
    return resolvedMode
  }

  fun currentMode(): ConnectionMode? = _currentMode.value ?: resolveSelectedMode()

  fun switchMode(mode: ConnectionMode) {
    require(mode in availableModes()) {
      "Connection mode ${mode.name} is not supported on this platform"
    }
    val current = currentMode()
    if (current == mode && ConnectionModeStore.get() == mode) {
      return
    }
    resetSession()
    ConnectionModeStore.save(mode)
    _currentMode.value = mode
  }

  fun resetSession() {
    AuthTokensStore.clearAllScopes()
    ClientIdStore.clearAllScopes()
    GradeScoreCacheStore.clearAllScopes()
    LocalAuthSessionStore.clearAllScopes()
    LocalCookieStore.clearAllScopes()
    CredentialStore.setAutoLogin(false)
    ApiClientProvider.reset()
    DefaultApiFactory.clearCachedBackends()
    LocalUpstreamClientProvider.reset()
    LocalJudgeApiCache.clearAll()
    GlobalTermRepository.instance.clear()
  }

  fun clearSelectedMode() {
    resetSession()
    ConnectionModeStore.clear()
    _currentMode.value = null
  }
}

internal object ModeScopedSessionStore {
  private const val LEGACY_PREFIX = ""

  fun scopedKey(key: String, mode: ConnectionMode? = ConnectionModeStore.get()): String {
    val effectiveMode = mode ?: ConnectionMode.SERVER_RELAY
    return "mode_${effectiveMode.storageKey}_$key"
  }

  fun legacyKey(key: String): String = "$LEGACY_PREFIX$key"
}
