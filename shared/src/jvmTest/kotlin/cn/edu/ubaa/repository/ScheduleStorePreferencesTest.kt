package cn.edu.ubaa.repository

import cn.edu.ubaa.model.dto.*
import com.russhwolf.settings.PreferencesSettings
import java.util.UUID
import java.util.prefs.Preferences
import kotlin.test.*
import kotlinx.datetime.LocalDate
import kotlinx.serialization.json.Json

class ScheduleStorePreferencesTest {
  @Test
  fun `真实桌面存储可以保存和重新读取超过单值限制的整学期课表`() {
    val term = Term("20261", "示例学期", true, 0)
    val start = LocalDate.parse("2026-09-07").toEpochDays()
    val weeks =
        (1..30).map {
          Week(
              LocalDate.fromEpochDays(start + (it - 1) * 7).toString(),
              LocalDate.fromEpochDays(start + (it - 1) * 7 + 6).toString(),
              term.itemCode,
              false,
              it,
              "第${it}周",
          )
        }
    val course =
        CourseClass(
            "sample",
            "示例课程🧪",
            "class-1",
            "2",
            "08:00",
            "09:35",
            1,
            2,
            "示例教室",
            "示例教师",
            null,
            null,
            1,
        )
    val snapshots =
        listOf(
            SemesterSchedule(
                listOf(term),
                term.itemCode,
                weeks,
                weeks.associate {
                  it.serialNumber to WeeklySchedule(listOf(course), term.itemCode, term.itemName)
                },
            )
        )
    assertTrue(Json.encodeToString(snapshots).length > Preferences.MAX_VALUE_LENGTH)
    val original = ScheduleStore.settings
    val node = Preferences.userRoot().node("ubaa-tests/schedule-${UUID.randomUUID()}")
    try {
      ScheduleStore.settings = PreferencesSettings(node)
      ScheduleStore.write("sample-account", snapshots)
      node.flush()
      ScheduleStore.settings = PreferencesSettings(node)
      assertEquals(snapshots, ScheduleStore.read("sample-account"))
      assertTrue(node.keys().all { node.get(it, "").length <= Preferences.MAX_VALUE_LENGTH })
    } finally {
      ScheduleStore.settings = original
      node.removeNode()
    }
  }
}
