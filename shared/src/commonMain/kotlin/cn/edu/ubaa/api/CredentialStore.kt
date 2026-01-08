package cn.edu.ubaa.api

import com.russhwolf.settings.Settings

/** 凭据存储：用于记住密码和自动登录 */
object CredentialStore {
  private const val KEY_USERNAME = "saved_username"
  private const val KEY_PASSWORD = "saved_password"
  private const val KEY_REMEMBER_PASSWORD = "remember_password"
  private const val KEY_AUTO_LOGIN = "auto_login"

  private val settings: Settings = Settings()

  fun saveCredentials(username: String, password: String) {
    settings.putString(KEY_USERNAME, username)
    settings.putString(KEY_PASSWORD, password)
  }

  fun getUsername(): String? = settings.getStringOrNull(KEY_USERNAME)

  fun getPassword(): String? = settings.getStringOrNull(KEY_PASSWORD)

  fun setRememberPassword(enabled: Boolean) {
    settings.putBoolean(KEY_REMEMBER_PASSWORD, enabled)
    if (!enabled) {
      settings.remove(KEY_USERNAME)
      settings.remove(KEY_PASSWORD)
      setAutoLogin(false)
    }
  }

  fun isRememberPassword(): Boolean = settings.getBoolean(KEY_REMEMBER_PASSWORD, false)

  fun setAutoLogin(enabled: Boolean) {
    settings.putBoolean(KEY_AUTO_LOGIN, enabled)
    if (enabled) {
      setRememberPassword(true)
    }
  }

  fun isAutoLogin(): Boolean = settings.getBoolean(KEY_AUTO_LOGIN, false)

  fun clear() {
    settings.remove(KEY_USERNAME)
    settings.remove(KEY_PASSWORD)
    settings.remove(KEY_REMEMBER_PASSWORD)
    settings.remove(KEY_AUTO_LOGIN)
  }
}
