package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.*
import kotlin.test.*
import kotlinx.datetime.LocalDate

class GsmisScheduleTest {
  private val terms = listOf(Term("20261", "示例学期", true, 0))
  private val body =
      """{
    "code":1,
    "rwList":[{"BJDM":"sample","XNXQDM":"20261","SCSKRQ":"2026-09-14"}],
    "jgList":[{"BJDM":"sample","KCDM":"demo","KCMC":"示例课程","XQ":1,
      "KSJCDM":1,"JSJCDM":2,"ZCBH":"0101","JCFADM":"01","JGJSXM":"示例教师"}],
    "jcfaList":[{"DM":"01","skjcList":[
      {"JCFADM":"01","DM":"1","KSSJ":800,"JSSJ":845},
      {"JCFADM":"01","DM":"2","KSSJ":850,"JSSJ":935},
      {"JCFADM":"01","DM":"3","KSSJ":950,"JSSJ":1035}]}]
  }"""

  @Test
  fun missingRowSchemeUsesOnlyTheSoleDeclaredScheme() {
    val missing =
        body.replace("\"ZCBH\":\"0101\",\"JCFADM\":\"01\"", "\"ZCBH\":\"0101\",\"JCFADM\":null")
    for (input in
        listOf(
            missing,
            missing.replace("\"JCFADM\":null,", ""),
            missing.replace("\"JCFADM\":null", "\"JCFADM\":\" \""),
        )) {
      val data = parseGsmisSchedule(input, terms, "20261")
      val course = data.weekly("20261", 2).arrangedList.single()
      assertEquals("08:00", course.beginTime)
      assertEquals("09:35", course.endTime)
      assertEquals(3, data.weekly("20261", 2).sectionTimes.size)
    }
    assertFailsWith<IllegalArgumentException> {
      parseGsmisSchedule(
          missing.replace("\"jcfaList\":[", "\"jcfaList\":[{\"DM\":\"02\",\"skjcList\":[]},"),
          terms,
          "20261",
      )
    }
    assertFailsWith<IllegalArgumentException> {
      parseGsmisSchedule(
          missing.replace("\"DM\":\"01\",\"skjcList\"", "\"skjcList\""),
          terms,
          "20261",
      )
    }
    // 多方案中已有明确编号的课程仍按该编号解析。
    val multiple = body.replace("\"jcfaList\":[", "\"jcfaList\":[{\"DM\":\"02\",\"skjcList\":[]},")
    assertEquals(
        "08:00",
        parseGsmisSchedule(multiple, terms, "20261")
            .weekly("20261", 2)
            .arrangedList
            .single()
            .beginTime,
    )
    // 已明确指定其他方案时，不能用唯一方案覆盖它。
    assertFails {
      parseGsmisSchedule(missing.replace("\"JCFADM\":null", "\"JCFADM\":\"02\""), terms, "20261")
    }
  }

  @Test
  fun mapsWeeksAndCompleteTimelineAndRejectsInvalidData() {
    val data = parseGsmisSchedule(body, terms, "20261")
    assertEquals("2026-09-07", data.weeks("20261", LocalDate.parse("2026-09-08")).first().startDate)
    assertTrue(data.weekly("20261", 1).arrangedList.isEmpty())
    assertEquals(3, data.weekly("20261", 1).sectionTimes.size)
    val course = data.weekly("20261", 2).arrangedList.single()
    assertEquals("08:00", course.beginTime)
    assertEquals("09:35", course.endTime)
    assertEquals(2, course.endSection)
    assertEquals("示例教师", course.weeksAndTeachers)
    assertFails { parseGsmisSchedule(body.replace("2026-09-14", "2026-09-15"), terms, "20261") }
    assertFails { parseGsmisSchedule(body.replace("\"JSJCDM\":2", "\"JSJCDM\":4"), terms, "20261") }
    assertFails { parseGsmisSchedule(body.replace("\"code\":1", "\"code\":0"), terms, "20261") }
    assertFails { parseGsmisSchedule(body.replace("20261", "20253"), terms, "20261") }
  }
}
