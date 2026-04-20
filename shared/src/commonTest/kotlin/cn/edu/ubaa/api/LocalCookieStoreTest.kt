package cn.edu.ubaa.api

import com.russhwolf.settings.MapSettings
import io.ktor.http.Cookie
import io.ktor.http.Url
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlinx.coroutines.test.runTest

class LocalCookieStoreTest {
  @BeforeTest
  fun setup() {
    ConnectionModeStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    LocalCookieStore.clearAllScopes()
    ConnectionModeStore.clear()
  }

  @Test
  fun `cookies without explicit path use request directory as default path`() = runTest {
    val storage = PersistentLocalCookieStorage(ConnectionMode.DIRECT)

    storage.addCookie(
        Url("https://spoc.buaa.edu.cn/spocnewht/cas"),
        Cookie(
            name = "SESSION",
            value = "session-1",
            domain = "spoc.buaa.edu.cn",
        ),
    )

    val cookies = storage.get(Url("https://spoc.buaa.edu.cn/spocnewht/sys/casLogin"))

    assertEquals(listOf("SESSION"), cookies.map { it.name })
  }
}
