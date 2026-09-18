package cn.edu.ubaa.api

import cn.edu.ubaa.api.feature.IhomeException
import cn.edu.ubaa.api.feature.IhomeProtocol
import cn.edu.ubaa.model.dto.IhomeScope
import kotlin.test.*
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class IhomeProtocolTest {
  @Test
  fun `失败封装的混合类型不会被当成成功`() {
    val error =
        assertFailsWith<IhomeException> {
          IhomeProtocol.envelope(
              """{"code":40001,"success":"","error":true,"data":[],"message":"含敏感上游内容"}"""
          )
        }
    assertEquals("ihome_business", error.code)
    assertFalse(error.message.orEmpty().contains("敏感"))
  }

  @Test
  fun `列表与评价包装分别解析且不泄露用户资料`() {
    val detail =
        """{"id":42,"content":"测试诉求","is_follow":1,"follow_count":3,"user":{"name":"真实姓名占位","phone":"隐私电话占位"}}"""
    val page =
        IhomeProtocol.page(
            Json.parseToJsonElement(
                """{"current_page":1,"last_page":2,"total":3,"per_page":"2","data":[$detail]}"""
            ),
            IhomeScope.PUBLIC,
        )
    assertEquals(42, page.entries.single().appeal.id)
    assertTrue(page.entries.single().appeal.isFollowed == true)
    assertNull(page.entries.single().appeal.isSupported)
    assertFalse(Json.encodeToString(page).contains("隐私"))
    assertFalse(Json.encodeToString(page).contains("真实姓名"))
    val evaluated =
        IhomeProtocol.page(
            Json.parseToJsonElement(
                """{"current_page":1,"last_page":1,"total":1,"data":[{"id":9,"speed":5,"satisfaction":4,"degree":3,"user":null,"avg_grade":"4.0","appeal":$detail}]}"""
            ),
            IhomeScope.APPRAISED,
        )
    assertEquals(9, evaluated.entries.single().evaluation?.id)
    assertEquals(42, evaluated.entries.single().appeal.id)
  }

  @Test
  fun `完整详情保留当前轮次进度与官方回复`() {
    val detail =
        IhomeProtocol.appeal(
            Json.parseToJsonElement(
                """{
      "id":42,"content":"测试","is_restart":1,"is_user":1,
      "appeal_reply":[{"content":"官方答复","department":{"name":"服务中心"},"created_at":"2026-09-17"}],
      "change_history":[{"contents":"旧轮次","restart":0},{"contents":"本轮分办","restart":1}]
    }"""
            )
        )
    assertTrue(detail.isMine)
    assertEquals("服务中心", detail.replies.single().department)
    assertEquals("本轮分办", detail.history.single().content)
  }

  @Test
  fun `未知形状不会静默伪装为空列表`() {
    assertFailsWith<IhomeException> {
      IhomeProtocol.page(Json.parseToJsonElement("{}"), IhomeScope.PUBLIC)
    }
    assertFailsWith<IhomeException> { IhomeProtocol.appeal(Json.parseToJsonElement("[]")) }
  }
}
