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
    "jcfaList":[{"skjcList":[
      {"JCFADM":"01","DM":"1","KSSJ":800,"JSSJ":845},
      {"JCFADM":"01","DM":"2","KSSJ":850,"JSSJ":935},
      {"JCFADM":"01","DM":"3","KSSJ":950,"JSSJ":1035}]}]
  }"""

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
