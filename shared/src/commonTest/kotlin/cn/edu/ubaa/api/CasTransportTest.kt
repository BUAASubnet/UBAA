package cn.edu.ubaa.api

import cn.edu.ubaa.api.auth.secureCasTransportUrl
import kotlin.test.Test
import kotlin.test.assertEquals

class CasTransportTest {
  @Test
  fun `只升级 SSO 的默认 HTTP 端口且保留嵌套查询编码`() {
    val suffix =
        "/login?service=https%3A%2F%2Fuc.buaa.edu.cn%2Fapi%2Flogin%3Ftarget%3Da%252Bb&ticket=synthetic"
    assertEquals(
        "https://sso.buaa.edu.cn$suffix",
        secureCasTransportUrl("http://sso.buaa.edu.cn$suffix"),
    )
    assertEquals(
        "https://sso.buaa.edu.cn$suffix",
        secureCasTransportUrl("http://sso.buaa.edu.cn:80$suffix"),
    )
    for (url in
        listOf(
            "https://sso.buaa.edu.cn$suffix",
            "http://sso.buaa.edu.cn:8080$suffix",
            "http://sso.buaa.edu.cn.example.org$suffix",
            "http://i.buaa.edu.cn/api/authLogin",
        )) {
      assertEquals(url, secureCasTransportUrl(url))
    }
  }
}
