package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.parseGsmisSchedule
import cn.edu.ubaa.model.dto.parseGsmisTerms
import java.io.File
import kotlin.test.*
import kotlinx.datetime.LocalDate
import kotlinx.serialization.json.*

class GsmisScheduleSampleTest {
  @Test
  fun suppliedScheduleMatchesEverySectionOfEveryWeek() {
    val path = System.getProperty("gsmisSampleDir")
    org.junit.Assume.assumeTrue("未指定 GSMIS 本地样本", path != null)
    val dir = File(requireNotNull(path))
    val body = File(dir, "课表响应.txt").readText()
    val terms = parseGsmisTerms(File(dir, "学期候选响应.txt").readText())
    val data = parseGsmisSchedule(body, terms, "20261")
    val weeks = data.weeks("20261", LocalDate.parse("2026-09-08"))
    assertEquals("2026-09-07", weeks.first().startDate)
    assertEquals(30, weeks.size)
    val rows = Json.parseToJsonElement(body).jsonObject.getValue("jgList").jsonArray
    for (week in 1..30) {
      val actual = data.weekly("20261", week)
      assertEquals(14, actual.sectionTimes.size)
      val expectedSections =
          rows
              .filter { it.jsonObject.getValue("ZCBH").jsonPrimitive.content[week - 1] == '1' }
              .flatMap { value ->
                val row = value.jsonObject
                (row.getValue("KSJCDM").jsonPrimitive.int..row.getValue("JSJCDM").jsonPrimitive.int)
                    .map {
                      "${row.getValue("BJDM").jsonPrimitive.content}/${row.getValue("XQ").jsonPrimitive.int}/$it/${row["JASMC"]}"
                    }
              }
              .toSet()
      val actualSections =
          actual.arrangedList
              .flatMap { course ->
                (course.beginSection!!..course.endSection!!).map {
                  "${course.courseSerialNo}/${course.dayOfWeek}/$it/${JsonPrimitive(course.placeName)}"
                }
              }
              .toSet()
      assertEquals(expectedSections, actualSections, "第 $week 周")
    }
    assertFails { parseGsmisSchedule(body.replace("2026-09-14", "2026-09-21"), terms, "20261") }
  }
}
