package cn.edu.ubaa.bykc

import cn.edu.ubaa.model.dto.BykcCourseDto
import cn.edu.ubaa.model.dto.BykcCourseStatus
import kotlin.test.*
import kotlinx.serialization.json.Json

/** BYKC 数据模型序列化测试 */
class BykcModelsTest {

  private val json = Json { ignoreUnknownKeys = true }

  @Test
  fun `BykcApiResponse can parse success response`() {
    val jsonStr =
      """
      {
          "status": "0",
          "errmsg": "请求成功",
          "token": null,
          "data": {
              "id": 12345,
              "employeeId": "20201234",
              "realName": "张三",
              "studentNo": "20201234",
              "studentType": "BENKE",
              "classCode": "202011",
              "noticeSwitch": true,
              "delFlag": 0
          }
      }
      """
        .trimIndent()

    val response = json.decodeFromString<BykcApiResponse<BykcUserProfile>>(jsonStr)

    assertTrue(response.isSuccess)
    assertEquals("0", response.status)
    assertEquals("请求成功", response.errmsg)
    assertNotNull(response.data)
    assertEquals(12345L, response.data?.id)
    assertEquals("20201234", response.data?.employeeId)
    assertEquals("张三", response.data?.realName)
  }

  @Test
  fun `BykcApiResponse can parse error response`() {
    val jsonStr =
      """
      {
          "status": "1",
          "errmsg": "已报名过该课程，请不要重复报名",
          "token": null,
          "data": null
      }
      """
        .trimIndent()

    val response = json.decodeFromString<BykcApiResponse<String>>(jsonStr)

    assertFalse(response.isSuccess)
    assertEquals("1", response.status)
    assertTrue(response.errmsg.contains("重复报名"))
    assertNull(response.data)
  }

  @Test
  fun `BykcCourse can parse full course data`() {
    val jsonStr =
      """
      {
          "id": 8748,
          "courseName": "AI时代,建构英语学习新思维",
          "coursePosition": "学院路校区主楼219教室",
          "courseContact": "李安琪",
          "courseContactMobile": "18321571726",
          "courseTeacher": "陈琦",
          "courseCreateDate": "2025-11-25 10:17:48",
          "courseStartDate": "2025-11-26 19:00:00",
          "courseEndDate": "2025-11-26 21:00:00",
          "courseSelectStartDate": "2025-11-25 19:00:00",
          "courseSelectEndDate": "2025-11-26 18:00:00",
          "courseCancelEndDate": "2025-11-26 18:00:00",
          "courseNewKind1": {
              "id": 60,
              "kindName": "博雅课程",
              "parentId": 0,
              "delFlag": 0
          },
          "courseNewKind2": {
              "id": 55,
              "kindName": "德育",
              "parentId": 60,
              "delFlag": 0
          },
          "courseMaxCount": 220,
          "courseCurrentCount": 150,
          "courseCampus": "ALL",
          "courseSignType": 2,
          "selected": false,
          "delFlag": 0
      }
      """
        .trimIndent()

    val course = json.decodeFromString<BykcCourse>(jsonStr)

    assertEquals(8748L, course.id)
    assertEquals("AI时代,建构英语学习新思维", course.courseName)
    assertEquals("学院路校区主楼219教室", course.coursePosition)
    assertEquals("陈琦", course.courseTeacher)
    assertEquals(220, course.courseMaxCount)
    assertEquals(150, course.courseCurrentCount)
    assertEquals("博雅课程", course.courseNewKind1?.kindName)
    assertEquals("德育", course.courseNewKind2?.kindName)
    assertEquals(false, course.selected)
  }

  @Test
  fun `BykcCoursePageResult can parse paginated response`() {
    val jsonStr =
      """
      {
          "content": [
              {
                  "id": 1001,
                  "courseName": "课程A",
                  "courseMaxCount": 100,
                  "courseCurrentCount": 50,
                  "selected": false,
                  "delFlag": 0
              },
              {
                  "id": 1002,
                  "courseName": "课程B",
                  "courseMaxCount": 200,
                  "courseCurrentCount": 200,
                  "selected": true,
                  "delFlag": 0
              }
          ],
          "totalElements": 50,
          "totalPages": 5,
          "size": 10,
          "number": 0,
          "numberOfElements": 2
      }
      """
        .trimIndent()

    val result = json.decodeFromString<BykcCoursePageResult>(jsonStr)

    assertEquals(2, result.content.size)
    assertEquals(50, result.totalElements)
    assertEquals(5, result.totalPages)

    val course1 = result.content[0]
    assertEquals(1001L, course1.id)
    assertEquals("课程A", course1.courseName)
    assertEquals(false, course1.selected)

    val course2 = result.content[1]
    assertEquals(1002L, course2.id)
    assertEquals(true, course2.selected)
  }

  @Test
  fun `BykcSignConfig can parse sign configuration`() {
    val jsonStr =
      """
      {
          "signStartDate": "2025-11-26 18:50:00",
          "signEndDate": "2025-11-26 19:10:00",
          "signOutStartDate": "2025-11-26 21:00:00",
          "signOutEndDate": "2025-11-26 21:20:00",
          "signPointList": [
              {"lat": 39.98970511198574, "lng": 116.35744239383477, "radius": 161.70647565670006},
              {"lat": 39.98971836466707, "lng": 116.35744239383483, "radius": 153.6079635389795}
          ]
      }
      """
        .trimIndent()

    val config = json.decodeFromString<BykcSignConfig>(jsonStr)

    assertEquals("2025-11-26 18:50:00", config.signStartDate)
    assertEquals("2025-11-26 19:10:00", config.signEndDate)
    assertEquals("2025-11-26 21:00:00", config.signOutStartDate)
    assertEquals("2025-11-26 21:20:00", config.signOutEndDate)
    assertEquals(2, config.signPointList.size)

    val point1 = config.signPointList[0]
    assertEquals(39.98970511198574, point1.lat, 0.0001)
    assertEquals(116.35744239383477, point1.lng, 0.0001)
    assertTrue(point1.radius > 100)
  }

  @Test
  fun `BykcCourseDto serialization works correctly`() {
    val dto =
      BykcCourseDto(
        id = 1234L,
        courseName = "测试课程",
        coursePosition = "测试地点",
        courseTeacher = "测试教师",
        courseStartDate = "2025-11-26 19:00:00",
        courseEndDate = "2025-11-26 21:00:00",
        courseSelectStartDate = "2025-11-25 19:00:00",
        courseSelectEndDate = "2025-11-26 18:00:00",
        courseMaxCount = 100,
        courseCurrentCount = 50,
        category = "博雅课程",
        subCategory = "德育",
        status = BykcCourseStatus.AVAILABLE,
        selected = false,
        courseDesc = "课程描述",
      )

    val serialized = json.encodeToString(BykcCourseDto.serializer(), dto)
    val deserialized = json.decodeFromString<BykcCourseDto>(serialized)

    assertEquals(dto.id, deserialized.id)
    assertEquals(dto.courseName, deserialized.courseName)
    assertEquals(dto.status, deserialized.status)
    assertEquals(dto.category, deserialized.category)
  }

  @Test
  fun `BykcCourseStatusEnum enum has correct display names`() {
    assertEquals("已过期", BykcCourseStatusEnum.EXPIRED.displayName)
    assertEquals("已选", BykcCourseStatusEnum.SELECTED.displayName)
    assertEquals("预告", BykcCourseStatusEnum.PREVIEW.displayName)
    assertEquals("已结束", BykcCourseStatusEnum.ENDED.displayName)
    assertEquals("人数已满", BykcCourseStatusEnum.FULL.displayName)
    assertEquals("可选", BykcCourseStatusEnum.AVAILABLE.displayName)
  }

  @Test
  fun `BykcCourseStatus constants have correct values`() {
    assertEquals("过期", BykcCourseStatus.EXPIRED)
    assertEquals("已选", BykcCourseStatus.SELECTED)
    assertEquals("预告", BykcCourseStatus.PREVIEW)
    assertEquals("结束", BykcCourseStatus.ENDED)
    assertEquals("满员", BykcCourseStatus.FULL)
    assertEquals("可选", BykcCourseStatus.AVAILABLE)
  }
}
