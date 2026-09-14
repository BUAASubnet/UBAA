package cn.edu.ubaa.api

import cn.edu.ubaa.model.dto.GraduateSchedule
import cn.edu.ubaa.model.dto.removeGraduateWebVpnScripts
import kotlin.test.*
import kotlinx.datetime.LocalDate

class GraduateScheduleTest {
  @Test
  fun repairsOnlyKnownWebVpnInjectionAndPreservesSchedule() {
    val injection =
        """<script>
var __vpn_hostname_data = "d.buaa.edu.cn";
var __vpn_js_file = "/wengine-vpn/js/main.js?ver=test";
</script><script src="/wengine-vpn/js/main.js?ver=test" charset="utf-8"></script>"""
    val damaged = body.replace("\"XF\":2", "\"XF\":2,\"PKSJDDMS\":\"教室<br/>$injection\"")
    assertFailsWith<kotlinx.serialization.SerializationException> {
      kotlinx.serialization.json.Json.parseToJsonElement(damaged)
    }
    val repaired = GraduateSchedule.parse(damaged)
    val original = GraduateSchedule.parse(body)
    assertEquals(original.terms(), repaired.terms())
    assertEquals(
        original.weeks("20261", LocalDate.parse("2026-09-07")),
        repaired.weeks("20261", LocalDate.parse("2026-09-07")),
    )
    for (week in 1..4) assertEquals(original.weekly("20261", week), repaired.weekly("20261", week))
    assertTrue(removeGraduateWebVpnScripts(damaged).contains("教室<br/>"))
    val unrelated = "<script>var course = \"example\";</script>"
    assertEquals(unrelated, removeGraduateWebVpnScripts(unrelated))
    assertFails { GraduateSchedule.parse(damaged.replace(injection, unrelated)) }
    // 合法 JSON 中的网页文本不能被清理掉。
    val valid = body.replace("示例课程", "示例课程<script>plain text</script>")
    assertEquals(
        "示例课程<script>plain text</script>",
        GraduateSchedule.parse(valid).weekly("20261", 2).arrangedList.single().courseName,
    )
  }

  private val row =
      """{"BJDM":"class-a","KCDM":"course-a","KCMC":"示例课程","XNXQDM":"20261","ZCBH":"0101","ZCMC":"2,4周","XQ":1,"KSJCDM":11,"JSJCDM":11,"KSSJ":1900,"JSSJ":1945,"JASMC":"示例教室","JSXM":"教师甲,教师乙"}"""
  private val next =
      row.replace("\"KSJCDM\":11", "\"KSJCDM\":12")
          .replace("\"JSJCDM\":11", "\"JSJCDM\":12")
          .replace("1900", "1950")
          .replace("1945", "2035")
          .replace("教师甲,教师乙", "教师乙,教师甲")
  private val body =
      """{"results":[$next,$row,$row],"xkjgList":[{"SFYXXKJG":0,"BJDM":"class-a","XNXQDM":"20261","XNXQMC":"示例学期","XF":2},{"BJDM":"unarranged","XNXQDM":"20261","SFYXXKJG":0}],"rqpkjgallList":[{"bjdm":"class-a","kssj":1900,"jssj":1945,"rqs":["2026-09-14","2026-09-28"]}]}"""

  @Test
  fun mapsTermsWeeksAndTodayWithoutDuplicatingSections() {
    val schedule = GraduateSchedule.parse(body)
    assertEquals("示例学期", schedule.terms().single().itemName)
    val weeks = schedule.weeks("20261", LocalDate.parse("2026-09-14"))
    assertEquals("2026-09-07", weeks.first().startDate)
    assertEquals(2, weeks.single { it.curWeek }.serialNumber)
    val course = schedule.weekly("20261", 2).arrangedList.single()
    assertEquals(11, course.beginSection)
    assertEquals(12, course.endSection)
    assertEquals("19:00", course.beginTime)
    assertEquals("20:35", course.endTime)
    assertEquals("2", course.credit)
    assertTrue(schedule.weekly("20261", 3).arrangedList.isEmpty())
    assertEquals(1, schedule.today(LocalDate.parse("2026-09-14")).size)
    assertTrue(schedule.today(LocalDate.parse("2026-09-15")).isEmpty())
  }

  @Test
  fun rejectsInvalidAndInconsistentUpstreamData() {
    assertFails { GraduateSchedule.parse("{}") }
    assertFails { GraduateSchedule.parse(body.replace("\"XQ\":1", "\"XQ\":0")) }
    assertFails { GraduateSchedule.parse(body.replace("1945", "1965")) }
    val inconsistent = GraduateSchedule.parse(body.replace("2026-09-28", "2026-09-29"))
    assertFails { inconsistent.weeks("20261", LocalDate.parse("2026-09-14")) }
    assertFails { GraduateSchedule.parse(body).weekly("missing", 1) }
  }

  @Test
  fun onlyConfirmedClassesAppearEvenWhenPreselectionSharesCourseCodeOrClassId() {
    val preselectedRow = row.replace("class-a", "class-pre")
    val mixed =
        body
            .replace("\"results\":[", "\"results\":[$preselectedRow,")
            .replace(
                "\"xkjgList\":[",
                "\"xkjgList\":[{\"BJDM\":\"class-pre\",\"XNXQDM\":\"20261\",\"SFYXXKJG\":1},{\"BJDM\":\"class-a\",\"XNXQDM\":\"20261\",\"SFYXXKJG\":1,\"XF\":99},",
            )
            .replace(
                "\"rqpkjgallList\":[",
                "\"rqpkjgallList\":[{\"bjdm\":\"class-pre\",\"kssj\":1900,\"jssj\":1945,\"rqs\":[\"2026-10-14\",\"2026-10-28\"]},",
            )
    val original = GraduateSchedule.parse(body)
    val selected = GraduateSchedule.parse(mixed)
    for (week in 1..4) assertEquals(original.weekly("20261", week), selected.weekly("20261", week))
    assertEquals(
        original.today(LocalDate.parse("2026-09-14")),
        selected.today(LocalDate.parse("2026-09-14")),
    )
    assertEquals("2", selected.weekly("20261", 2).arrangedList.single().credit)
  }

  @Test
  fun preselectionOnlyKeepsSemesterButProducesNoFormalCourses() {
    val selected = GraduateSchedule.parse(body.replace("\"SFYXXKJG\":0", "\"SFYXXKJG\":1"))
    assertEquals("20261", selected.terms().single().itemCode)
    assertTrue(selected.weeks("20261", LocalDate.parse("2026-09-14")).isEmpty())
    assertTrue(selected.weekly("20261", 2).arrangedList.isEmpty())
    assertTrue(selected.today(LocalDate.parse("2026-09-14")).isEmpty())
    assertFails { GraduateSchedule.parse(body.replace("\"SFYXXKJG\":0", "\"SFYXXKJG\":null")) }
  }

  @Test
  fun validEmptyResponseIsDifferentFromInvalidResponse() {
    val empty = GraduateSchedule.parse("""{"results":[],"xkjgList":[],"rqpkjgallList":[]}""")
    assertTrue(empty.terms().isEmpty())
    assertTrue(empty.today(LocalDate.parse("2026-09-14")).isEmpty())
  }
}
