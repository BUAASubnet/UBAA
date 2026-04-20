package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class LocalAuthSessionStoreTest {
  @BeforeTest
  fun setup() {
    ConnectionModeStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalAuthSessionStore.clearAllScopes()
    ConnectionModeStore.clear()
  }

  @Test
  fun `local auth sessions are isolated by connection mode`() {
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Direct User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )

    ConnectionModeStore.save(ConnectionMode.WEBVPN)
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22374444",
            user = UserData(name = "Vpn User", schoolid = "22374444"),
            authenticatedAt = "2026-04-20T09:00:00Z",
            lastActivity = "2026-04-20T09:30:00Z",
        )
    )

    ConnectionModeStore.save(ConnectionMode.DIRECT)
    assertEquals("22373333", LocalAuthSessionStore.get()?.username)
    assertEquals("Direct User", LocalAuthSessionStore.get()?.user?.name)

    ConnectionModeStore.save(ConnectionMode.WEBVPN)
    assertEquals("22374444", LocalAuthSessionStore.get()?.username)
    assertEquals("Vpn User", LocalAuthSessionStore.get()?.user?.name)

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)
    assertNull(LocalAuthSessionStore.get())
  }
}
