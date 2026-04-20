package cn.edu.ubaa.api

import com.russhwolf.settings.MapSettings
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class LocalWebVpnSupportTest {
  @BeforeTest
  fun setup() {
    ConnectionModeStore.settings = MapSettings()
    ConnectionRuntime.clearSelectedMode()
  }

  @Test
  fun `webvpn codec round-trips https upstream url`() {
    val original = "https://spoc.buaa.edu.cn/spocnewht/cas?token=test-token"

    val wrapped = LocalWebVpnSupport.toWebVpnUrl(original)

    assertTrue(wrapped.startsWith("https://d.buaa.edu.cn/https/"))
    assertEquals(original, LocalWebVpnSupport.fromWebVpnUrl(wrapped))
  }

  @Test
  fun `webvpn codec round-trips custom port url`() {
    val original = "http://iclass.buaa.edu.cn:8081/app/course/stu_scan_sign.action?id=1"

    val wrapped = LocalWebVpnSupport.toWebVpnUrl(original)

    assertTrue(wrapped.startsWith("https://d.buaa.edu.cn/http-8081/"))
    assertEquals(original, LocalWebVpnSupport.fromWebVpnUrl(wrapped))
  }

  @Test
  fun `upstream url helper wraps direct upstream when current mode is webvpn`() {
    ConnectionModeStore.save(ConnectionMode.WEBVPN)
    ConnectionRuntime.resolveSelectedMode()

    val resolved = localUpstreamUrl("https://uc.buaa.edu.cn/api/uc/status")

    assertTrue(resolved.startsWith("https://d.buaa.edu.cn/https/"))
    assertEquals("https://uc.buaa.edu.cn/api/uc/status", LocalWebVpnSupport.fromWebVpnUrl(resolved))
  }
}
