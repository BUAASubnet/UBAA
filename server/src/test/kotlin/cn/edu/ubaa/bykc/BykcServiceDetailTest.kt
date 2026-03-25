package cn.edu.ubaa.bykc

import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals

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
}
