package cn.edu.ubaa.grade

import cn.edu.ubaa.auth.LoginException
import cn.edu.ubaa.auth.UnsupportedAcademicPortalException
import cn.edu.ubaa.auth.userFacingMessage
import io.ktor.http.HttpStatusCode
import kotlin.test.Test
import kotlin.test.assertEquals

class GradeRoutesTest {

  @Test
  fun loginExceptionMapsToInvalidToken() {
    val (status, code) = gradeErrorResponse(LoginException("session expired"))

    assertEquals(HttpStatusCode.Unauthorized, status)
    assertEquals("invalid_token", code)
  }

  @Test
  fun unsupportedPortalMapsToNotImplemented() {
    val (status, code) =
        gradeErrorResponse(UnsupportedAcademicPortalException("unsupported portal"))

    assertEquals(HttpStatusCode.NotImplemented, status)
    assertEquals("unsupported_portal", code)
  }

  @Test
  fun genericExceptionMapsToGradeError() {
    val (status, code) = gradeErrorResponse(IllegalStateException("boom"))

    assertEquals(HttpStatusCode.BadGateway, status)
    assertEquals("grade_error", code)
  }

  @Test
  fun gradeErrorHasUserFacingMessage() {
    assertEquals("成绩查询失败，请稍后重试", userFacingMessage("grade_error"))
  }
}
