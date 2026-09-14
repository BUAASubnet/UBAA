package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.GraduateSchedule
import cn.edu.ubaa.model.dto.removeGraduateWebVpnScripts
import cn.edu.ubaa.repository.ScheduleRepository
import cn.edu.ubaa.repository.SemesterSchedule
import java.io.File
import kotlin.test.*
import kotlinx.datetime.LocalDate
import kotlinx.serialization.json.*

/** 可选本地样本检查；原始响应留在仓库外，避免提交个人信息。 */
class GraduateScheduleSampleTest {
  @Test
  fun suppliedScheduleMatchesEveryWeek() {
    val path = System.getenv("UBAA_GRADUATE_SCHEDULE_SAMPLE")
    org.junit.Assume.assumeTrue("未指定本地课表样本", path != null)
    val body = File(requireNotNull(path)).readText()
    val schedule = GraduateSchedule.parse(body)
    val source = Json.parseToJsonElement(removeGraduateWebVpnScripts(body)).jsonObject
    val confirmed =
        source
            .getValue("xkjgList")
            .jsonArray
            .map { it.jsonObject }
            .filter { it.getValue("SFYXXKJG").jsonPrimitive.content == "0" }
            .map { it.getValue("BJDM").jsonPrimitive.content }
            .toSet()
    val rows =
        source.getValue("results").jsonArray.filter {
          it.jsonObject.getValue("BJDM").jsonPrimitive.content in confirmed
        }
    for (term in schedule.terms()) {
      val weeks = schedule.weeks(term.itemCode, LocalDate.parse("2026-09-07"))
      val snapshot =
          SemesterSchedule(
              schedule.terms(),
              term.itemCode,
              weeks,
              weeks.associate {
                it.serialNumber to schedule.weekly(term.itemCode, it.serialNumber)
              },
          )
      if (source.containsKey("skjcList")) {
        val times = snapshot.schedules.values.first().sectionTimes
        assertTrue(times.isNotEmpty(), "真实响应的作息表必须保存")
        assertTrue(times.all { it.start != null && it.end != null })
      }
      val restored = Json.decodeFromString<SemesterSchedule>(Json.encodeToString(snapshot))
      val offline =
          ScheduleRepository(
              account = { "sample" },
              read = { listOf(restored) },
              write = { _, _ -> error("read only") },
          )
      for (week in weeks) {
        val expected =
            rows
                .map { it.jsonObject }
                .filter {
                  it.getValue("XNXQDM").jsonPrimitive.content == term.itemCode &&
                      it.getValue("ZCBH").jsonPrimitive.content.getOrNull(week.serialNumber - 1) ==
                          '1'
                }
                .flatMap { row ->
                  (row.getValue("KSJCDM").jsonPrimitive.int..row.getValue("JSJCDM")
                              .jsonPrimitive
                              .int)
                      .map { section ->
                        Triple(
                            row.getValue("BJDM").jsonPrimitive.content,
                            row.getValue("XQ").jsonPrimitive.int,
                            section,
                        )
                      }
                }
                .toSet()
        val actual =
            offline
                .weekly(term.itemCode, week.serialNumber)
                .getOrThrow()
                .arrangedList
                .flatMap { course ->
                  (course.beginSection!!..course.endSection!!).map { section ->
                    Triple(course.courseSerialNo!!, course.dayOfWeek!!, section)
                  }
                }
                .toSet()
        assertEquals(expected, actual, "排课节次必须与上游位图一致")
      }
    }
  }
}
