package cn.edu.ubaa.ui

import cn.edu.ubaa.model.dto.Grade
import cn.edu.ubaa.ui.screens.grade.gradeDetailRows
import kotlin.test.Test
import kotlin.test.assertFalse
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
}
