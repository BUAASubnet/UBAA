package cn.edu.ubaa.api

import com.russhwolf.settings.Settings
import kotlin.uuid.ExperimentalUuidApi
import kotlin.uuid.Uuid

/** Simple multiplatform token store backed by persistent Settings. */
object TokenStore {
  private const val KEY_TOKEN = "auth_token"
  private var _settings: Settings? = null
  var settings: Settings
    get() = _settings ?: Settings().also { _settings = it }
    set(value) {
      _settings = value
    }

  fun save(token: String) {
    settings.putString(KEY_TOKEN, token)
  }

  fun get(): String? = settings.getStringOrNull(KEY_TOKEN)

  fun clear() {
    settings.remove(KEY_TOKEN)
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
    return settings.getStringOrNull(KEY_CLIENT_ID)
      ?: run {
        val newId = Uuid.random().toString()
        settings.putString(KEY_CLIENT_ID, newId)
        newId
      }
  }

  /** 获取 clientId（可能为 null） */
  fun get(): String? = settings.getStringOrNull(KEY_CLIENT_ID)

  /** 清除 clientId（通常不需要，除非要完全重置客户端） */
  fun clear() {
    settings.remove(KEY_CLIENT_ID)
  }
}
