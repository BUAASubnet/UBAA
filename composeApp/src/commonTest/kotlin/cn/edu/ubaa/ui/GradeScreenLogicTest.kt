package cn.edu.ubaa.ui

import cn.edu.ubaa.model.dto.Grade
import cn.edu.ubaa.ui.screens.grade.calculateGradeStatistics
import cn.edu.ubaa.ui.screens.grade.gradeDetailRows
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GradeScreenLogicTest {
  @Test
  fun `grade detail rows omit grade point`() {
    val rows =
        gradeDetailRows(
            Grade(
                courseCode = "MATH001",
                credit = 4.0,
                gradePoint = "4.0",
                courseAttribute = "必修",
                recognitionType = "百分制",
            )
        )

    assertFalse(rows.any { it.label == "绩点" })
    assertFalse(rows.any { it.value == "4.0" && it.label == "绩点" })
    assertTrue(rows.any { it.label == "课程号" && it.value == "MATH001" })
  }

  @Test
  fun `grade statistics weight numeric scores by credits`() {
    val statistics =
        calculateGradeStatistics(
            listOf(
                grade(score = "100", credit = 2.0),
                grade(score = "80", credit = 3.0),
            )
        )

    assertEquals(2, statistics.courseCount)
    assertEquals(5.0, statistics.totalCredits)
    assertEquals(3.55, statistics.gpa)
    assertEquals(88.0, statistics.weightedAverage)
  }

  @Test
  fun `grade statistics convert level scores and skip pass fail courses`() {
    val statistics =
        calculateGradeStatistics(
            listOf(
                grade(score = "优", credit = 2.0),
                grade(score = "良", credit = 2.0),
                grade(score = "通过", credit = 5.0),
                grade(score = "不通过", credit = 5.0),
            )
        )

    assertEquals(4, statistics.courseCount)
    assertEquals(14.0, statistics.totalCredits)
    assertEquals(3.75, statistics.gpa)
    assertEquals(90.0, statistics.weightedAverage)
  }

  @Test
  fun `grade statistics return empty averages when no course participates`() {
    val statistics =
        calculateGradeStatistics(
            listOf(
                grade(score = "通过", credit = 2.0),
                grade(score = "不通过", credit = 2.0),
            )
        )

    assertEquals(2, statistics.courseCount)
    assertEquals(4.0, statistics.totalCredits)
    assertNull(statistics.gpa)
    assertNull(statistics.weightedAverage)
  }
}

private fun grade(score: String, credit: Double): Grade = Grade(score = score, credit = credit)
