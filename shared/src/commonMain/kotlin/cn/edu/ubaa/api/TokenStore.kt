package cn.edu.ubaa.api

import com.russhwolf.settings.Settings

/** Simple multiplatform token store backed by persistent Settings. */
object TokenStore {
    private const val KEY_TOKEN = "auth_token"
    private val settings: Settings = Settings()

    fun save(token: String) {
        settings.putString(KEY_TOKEN, token)
    }

    fun get(): String? = settings.getStringOrNull(KEY_TOKEN)

    fun clear() {
        settings.remove(KEY_TOKEN)
    }
}
