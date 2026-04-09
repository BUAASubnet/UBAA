package cn.edu.ubaa.bykc

import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.runBlocking

class BykcServiceDetailTest {

  @Test
  fun `getCourseDetail maps select and cancel dates`() = runBlocking {
    val course =
        BykcCourse(
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

                override suspend fun queryCourseById(id: Long): BykcCourse = course
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
  fun `getChosenCourses maps cancel end date`() = runBlocking {
    val chosenCourse =
        BykcChosenCourse(
            id = 1L,
            selectDate = "2025-11-24 10:00:00",
            courseInfo =
                BykcCourse(
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
  fun `getCourseDetail exposes sign out availability during sign out window even when unsigned`() =
      runBlocking {
        val detail =
            createSignedCourseDetail(
                now = LocalDateTime.parse("2025-11-26T21:05:00"),
                checkin = 0,
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

  @Test
  fun `getCourseDetail uses semester containing now instead of first semester`() = runBlocking {
    val now = LocalDateTime.parse("2026-04-09T17:53:00")
    val service =
        BykcService(
            clientProvider = { _ ->
              object : BykcClient("test-user") {
                override suspend fun login(forceRefresh: Boolean): Boolean = true

                override suspend fun queryCourseById(id: Long): BykcCourse =
                    BykcCourse(
                        id = 9527L,
                        courseName = "耕趣农场劳动课",
                        courseSignConfig =
                            """
                            {
                              "signStartDate": "2026-04-09 16:20:00",
                              "signEndDate": "2026-04-09 16:40:00",
                              "signOutStartDate": "2026-04-09 17:50:00",
                              "signOutEndDate": "2026-04-09 18:15:00",
                              "signPointList": []
                            }
                            """
                                .trimIndent(),
                        courseMaxCount = 100,
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
                                ),
                                BykcSemester(
                                    id = 2L,
                                    semesterName = "2025-2026-2",
                                    semesterStartDate = "2026-02-23 00:00:00",
                                    semesterEndDate = "2026-07-12 23:59:59",
                                ),
                            )
                    )

                override suspend fun queryChosenCourse(
                    startDate: String,
                    endDate: String,
                ): List<BykcChosenCourse> {
                  return if (
                      startDate == "2026-02-23 00:00:00" && endDate == "2026-07-12 23:59:59"
                  ) {
                    listOf(
                        BykcChosenCourse(
                            id = 1L,
                            courseInfo = queryCourseById(9527L),
                            checkin = 5,
                            pass = 0,
                        )
                    )
                  } else {
                    emptyList()
                  }
                }
              }
            },
            nowProvider = { now },
        )

    val detail = service.getCourseDetail("test-user", 9527L)

    assertEquals(5, detail.checkin)
    assertFalse(detail.canSign)
    assertTrue(detail.canSignOut)
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

                  override suspend fun queryCourseById(id: Long): BykcCourse =
                      BykcCourse(
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
