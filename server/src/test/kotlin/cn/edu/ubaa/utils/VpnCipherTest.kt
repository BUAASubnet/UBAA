package cn.edu.ubaa.utils

import kotlin.test.Test
import kotlin.test.assertEquals

class VpnCipherTest {
  @Test
  fun `WebVPN还原保留iHome尾斜杠和登录片段`() {
    val wasEnabled = VpnCipher.isEnabled
    VpnCipher.isEnabled = true
    try {
      listOf(
              "http://i.buaa.edu.cn/web/#/login?type=0&token=fixture-token",
              "https://i.buaa.edu.cn/a//b/?q=test%2Bvalue",
          )
          .forEach { original ->
            assertEquals(original, VpnCipher.fromVpnUrl(VpnCipher.toVpnUrl(original)))
          }
    } finally {
      VpnCipher.isEnabled = wasEnabled
    }
  }

  @Test
  fun `from vpn url restores standard url with port query and fragment`() {
    val original =
        "https://iclass.buaa.edu.cn:8346/?loginName=abc%2Bdef%3D&type=jumpMyCenter#/MyCenter"
    val wasEnabled = VpnCipher.isEnabled
    VpnCipher.isEnabled = true

    try {
      val vpnUrl = VpnCipher.toVpnUrl(original)

      assertEquals(original, VpnCipher.fromVpnUrl(vpnUrl))
    } finally {
      VpnCipher.isEnabled = wasEnabled
    }
  }
}
