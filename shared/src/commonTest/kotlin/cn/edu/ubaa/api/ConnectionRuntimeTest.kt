package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.UserData
import com.russhwolf.settings.MapSettings
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ConnectionRuntimeTest {

  @BeforeTest
  fun setup() {
    val modeSettings = MapSettings()
    ConnectionModeStore.settings = modeSettings
    AuthTokensStore.settings = MapSettings()
    ClientIdStore.settings = MapSettings()
    CredentialStore.settings = MapSettings()
    LocalAuthSessionStore.settings = MapSettings()
    LocalCookieStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
    AuthTokensStore.clearAllScopes()
    ClientIdStore.clearAllScopes()
    CredentialStore.clear()
    LocalAuthSessionStore.clearAllScopes()
    LocalCookieStore.clearAllScopes()
    ConnectionRuntime.apiFactoryProvider = { DefaultApiFactory }
  }

  @Test
  fun `switching connection mode clears all scoped sessions and disables auto login`() {
    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)
    AuthTokensStore.save(
        StoredAuthTokens(
            accessToken = "relay-access",
            refreshToken = "relay-refresh",
        )
    )
    ClientIdStore.getOrCreate()

    ConnectionModeStore.save(ConnectionMode.DIRECT)
    AuthTokensStore.save(
        StoredAuthTokens(
            accessToken = "direct-access",
            refreshToken = "direct-refresh",
        )
    )
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Test User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )

    CredentialStore.saveCredentials("22373333", "secret")
    CredentialStore.setRememberPassword(true)
    CredentialStore.setAutoLogin(true)

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)

    ConnectionRuntime.switchMode(ConnectionMode.WEBVPN)

    assertEquals(ConnectionMode.WEBVPN, ConnectionRuntime.currentMode())
    assertNull(AuthTokensStore.get())
    assertNull(ClientIdStore.get())
    assertNull(LocalAuthSessionStore.get())
    assertFalse(CredentialStore.isAutoLogin())
    assertTrue(CredentialStore.isRememberPassword())
    assertEquals("22373333", CredentialStore.getUsername())
    assertEquals("secret", CredentialStore.getPassword())

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)
    assertNull(AuthTokensStore.get())
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    assertNull(AuthTokensStore.get())
  }

  @Test
  fun `direct mode auth service uses local persisted session contract by default`() {
    ConnectionModeStore.save(ConnectionMode.DIRECT)
    LocalAuthSessionStore.save(
        LocalAuthSession(
            username = "22373333",
            user = UserData(name = "Test User", schoolid = "22373333"),
            authenticatedAt = "2026-04-20T08:00:00Z",
            lastActivity = "2026-04-20T08:30:00Z",
        )
    )

    assertTrue(AuthService().hasPersistedSession())

    ConnectionModeStore.save(ConnectionMode.SERVER_RELAY)
    assertFalse(AuthService().hasPersistedSession())
  }
}
