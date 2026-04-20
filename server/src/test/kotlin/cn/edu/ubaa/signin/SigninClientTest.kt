package cn.edu.ubaa.signin

import kotlin.test.Test
import kotlin.test.assertEquals

class SigninClientTest {

  @Test
  fun `sanitizeSignInMessage maps not in class time error`() {
    val client = SigninClient(studentId = "24182104")

    try {
      assertEquals(
          "当前不是上课时间，无法签到",
          client.sanitizeSignInMessage(success = false, rawMessage = "当前时间不是上课时间！"),
      )
    } finally {
      client.close()
    }
  }
}
