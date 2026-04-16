package cn.edu.ubaa.bykc

import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class BykcServiceDetailTest {

  @Test
  fun `getCourseDetail maps select and cancel dates`() = runBlocking {
    val course =
        BykcRawCourse(
            id = 8748L,
            courseName = "AI时代,建构英语学习新思维",
            coursePosition = "学院路校区主楼219教室",
            courseTeacher = "陈琦",
            courseStartDate = "2025-11-26 19:00:00",
            courseEndDate = "2025-11-26 21:00:00",
            courseSelectStartDate = "2025-11-25 19:00:00",
            courseSelectEndDate = "2025-11-26 18:00:00",
            courseCancelEndDate = "2025-11-26 18:00:00",
            courseMaxCount = 220,
            courseCurrentCount = 150,
            selected = false,
        )

    val service =
        BykcService(
            clientProvider = { _ ->
              object : BykcClient("test-user") {
                override suspend fun login(forceRefresh: Boolean): Boolean = true

                override suspend fun queryCourseById(id: Long): BykcRawCourse = course
              }
            }
        )

    val detail = service.getCourseDetail(username = "test-user", courseId = course.id)

    assertEquals(course.courseSelectStartDate, detail.courseSelectStartDate)
    assertEquals(course.courseSelectEndDate, detail.courseSelectEndDate)
    assertEquals(course.courseCancelEndDate, detail.courseCancelEndDate)
    assertEquals(course.coursePosition, detail.coursePosition)
    assertEquals(course.courseTeacher, detail.courseTeacher)
  }

  @Test
  fun `getCourseDetail keeps useful detail fields and nullable enrollment`() = runBlocking {
    val course =
        BykcRawCourse(
            id = 9267L,
            courseName = "体验式团体心理沙龙",
            coursePosition = "沙河校区体育馆5楼501",
            courseContact = "曹雅璐",
            courseContactMobile = "13967341804",
            courseTeacher = "金珠",
            courseStartDate = "2026-04-29 14:30:00",
            courseEndDate = "2026-04-29 16:30:00",
            courseSelectStartDate = "2026-04-25 14:30:00",
            courseSelectEndDate = "2026-04-29 00:00:00",
            courseCancelEndDate = "2026-04-28 12:00:00",
            courseBelongCollege = BykcCollege(id = 61L, collegeName = "学生中心"),
            courseMaxCount = 30,
            courseCurrentCount = null,
            courseCampusList = listOf("全部校区"),
            courseCollegeList = listOf("全部学院"),
            courseTermList = listOf("全部年级"),
            courseGroupList = listOf("全部人群"),
            courseDesc = "<p>课程描述</p>",
            selected = false,
        )

    val service =
        BykcService(
            clientProvider = { _ ->
              object : BykcClient("test-user") {
                override suspend fun login(forceRefresh: Boolean): Boolean = true

                override suspend fun queryCourseById(id: Long): BykcRawCourse = course
              }
            }
        )

    val detail = service.getCourseDetail(username = "test-user", courseId = course.id)

    assertEquals("学生中心", detail.organizerCollegeName)
    assertEquals(listOf("全部校区"), detail.audienceCampuses)
    assertEquals(listOf("全部学院"), detail.audienceColleges)
    assertEquals(listOf("全部年级"), detail.audienceTerms)
    assertEquals(listOf("全部人群"), detail.audienceGroups)
    assertEquals("<p>课程描述</p>", detail.courseDesc)
    assertNull(detail.courseCurrentCount)
  }

  @Test
  fun `getChosenCourses maps cancel end date`() = runBlocking {
    val chosenCourse =
        BykcChosenCourse(
            id = 1L,
            selectDate = "2025-11-24 10:00:00",
            courseInfo =
                BykcRawCourse(
                    id = 8748L,
                    courseName = "AI时代,建构英语学习新思维",
                    courseCancelEndDate = "2025-11-26 18:00:00",
                    courseMaxCount = 220,
                ),
        )

    val service =
        BykcService(
            clientProvider = { _ ->
              object : BykcClient("test-user") {
                override suspend fun login(forceRefresh: Boolean): Boolean = true

                override suspend fun getAllConfig(): BykcAllConfig =
                    BykcAllConfig(
                        semester =
                            listOf(
                                BykcSemester(
                                    id = 1L,
                                    semesterName = "2025-2026-1",
                                    semesterStartDate = "2025-09-01 00:00:00",
                                    semesterEndDate = "2026-01-31 23:59:59",
                                )
                            )
                    )

                override suspend fun queryChosenCourse(
                    startDate: String,
                    endDate: String,
                ): List<BykcChosenCourse> = listOf(chosenCourse)
              }
            }
        )

    val chosenCourses = service.getChosenCourses("test-user")

    assertEquals(1, chosenCourses.size)
    assertEquals("2025-11-26 18:00:00", chosenCourses.first().courseCancelEndDate)
  }

  @Test
  fun `getCourseDetail exposes sign in availability during sign in window`() = runBlocking {
    val detail =
        createSignedCourseDetail(
            now = LocalDateTime.parse("2025-11-26T18:50:00"),
            checkin = 0,
            pass = 0,
        )

    assertTrue(detail.canSign)
    assertFalse(detail.canSignOut)
  }

  @Test
  fun `getCourseDetail exposes sign out availability at sign out boundary`() = runBlocking {
    val detail =
        createSignedCourseDetail(
            now = LocalDateTime.parse("2025-11-26T21:20:00"),
            checkin = 5,
            pass = 0,
        )

    assertFalse(detail.canSign)
    assertTrue(detail.canSignOut)
  }

  @Test
  fun `getCourseDetail keeps sign actions disabled outside window`() = runBlocking {
    val detail =
        createSignedCourseDetail(
            now = LocalDateTime.parse("2025-11-26T18:40:00"),
            checkin = 0,
            pass = 0,
        )

    assertFalse(detail.canSign)
    assertFalse(detail.canSignOut)
  }

  @Test
  fun `getCourseDetail keeps sign actions disabled after pass`() = runBlocking {
    val detail =
        createSignedCourseDetail(
            now = LocalDateTime.parse("2025-11-26T18:55:00"),
            checkin = 0,
            pass = 1,
        )

    assertFalse(detail.canSign)
    assertFalse(detail.canSignOut)
  }

  private suspend fun createSignedCourseDetail(
      now: LocalDateTime,
      checkin: Int?,
      pass: Int?,
  ) =
      BykcService(
              clientProvider = { _ ->
                object : BykcClient("test-user") {
                  override suspend fun login(forceRefresh: Boolean): Boolean = true

                  override suspend fun queryCourseById(id: Long): BykcRawCourse =
                      BykcRawCourse(
                          id = 8748L,
                          courseName = "AI时代,建构英语学习新思维",
                          coursePosition = "学院路校区主楼219教室",
                          courseTeacher = "陈琦",
                          courseStartDate = "2025-11-26 19:00:00",
                          courseEndDate = "2025-11-26 21:00:00",
                          courseSelectStartDate = "2025-11-25 19:00:00",
                          courseSelectEndDate = "2025-11-26 18:00:00",
                          courseCancelEndDate = "2025-11-26 18:00:00",
                          courseSignConfig =
                              """
                              {
                                "signStartDate": "2025-11-26 18:50:00",
                                "signEndDate": "2025-11-26 19:10:00",
                                "signOutStartDate": "2025-11-26 21:00:00",
                                "signOutEndDate": "2025-11-26 21:20:00",
                                "signPointList": []
                              }
                              """
                                  .trimIndent(),
                          courseMaxCount = 220,
                          courseCurrentCount = 150,
                          selected = true,
                      )

                  override suspend fun getAllConfig(): BykcAllConfig =
                      BykcAllConfig(
                          semester =
                              listOf(
                                  BykcSemester(
                                      id = 1L,
                                      semesterName = "2025-2026-1",
                                      semesterStartDate = "2025-09-01 00:00:00",
                                      semesterEndDate = "2026-01-31 23:59:59",
                                  )
                              )
                      )

                  override suspend fun queryChosenCourse(
                      startDate: String,
                      endDate: String,
                  ): List<BykcChosenCourse> =
                      listOf(
                          BykcChosenCourse(
                              id = 1L,
                              selectDate = "2025-11-24 10:00:00",
                              courseInfo = queryCourseById(8748L),
                              checkin = checkin,
                              pass = pass,
                          )
                      )
                }
              },
              nowProvider = { now },
          )
          .getCourseDetail(username = "test-user", courseId = 8748L)
}
