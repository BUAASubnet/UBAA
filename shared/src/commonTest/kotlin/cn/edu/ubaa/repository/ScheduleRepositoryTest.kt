package cn.edu.ubaa.repository

import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.api.feature.ScheduleApiBackend
import cn.edu.ubaa.model.dto.*
import com.russhwolf.settings.MapSettings
import kotlin.test.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import kotlinx.datetime.LocalDate

class ScheduleRepositoryTest {
  @Test
  fun `entire semester survives recreation and browsing never uses network`() = runTest {
    ScheduleStore.settings = MapSettings()
    ScheduleStore.useAccount("A")
    val backend = Backend()
    var date = LocalDate.parse("2026-09-07")
    fun repository() = ScheduleRepository(ScheduleApi { backend }, today = { date })
    val repo = repository()
    assertTrue(repo.terms().isFailure)
    assertTrue(repo.todayClasses().isFailure)
    assertEquals(0, backend.calls)
    assertTrue(repo.update().isSuccess)
    assertEquals(4, backend.calls) // 学期、周次、两周课表，今日课表无需额外请求。
    assertTrue(ScheduleStore.hasSavedSchedule())
    val offline = repository()
    backend.fail = true
    assertEquals("A课", offline.todayClasses().getOrThrow().single().bizName)
    assertEquals(2, offline.weeks("20261").getOrThrow().size)
    assertNotNull(offline.updatedAt("20261"))
    date = LocalDate.parse("2026-09-14")
    assertEquals(2, offline.weeks("20261").getOrThrow().single { it.curWeek }.serialNumber)
    assertEquals("B课", offline.todayClasses().getOrThrow().single().bizName)
    date = LocalDate.parse("2026-09-15")
    assertTrue(offline.todayClasses().getOrThrow().isEmpty())
    assertEquals(4, backend.calls)
    val before = ScheduleStore.read("A")
    assertTrue(offline.update().isFailure)
    assertEquals(before, ScheduleStore.read("A"))
    ScheduleStore.useAccount("B")
    assertTrue(offline.terms().isFailure)
    assertTrue(offline.todayClasses().isFailure)
    ScheduleStore.useAccount("A")
    assertEquals("A课", offline.weekly("20261", 1).getOrThrow().arrangedList.single().courseName)
    ScheduleStore.forgetAccount()
    assertFalse(ScheduleStore.hasSavedSchedule())
    assertTrue(offline.terms().isFailure)
  }

  @Test
  fun `partial import cancellation and account switch never overwrite saved semester`() = runTest {
    var account = "A"
    val storage = mutableMapOf<String, List<SemesterSchedule>>()
    val backend = Backend()
    val repo =
        ScheduleRepository(
            ScheduleApi { backend },
            { account },
            { storage[it].orEmpty() },
            { key, value -> storage[key] = value },
        )
    repo.update().getOrThrow()
    val before = storage.toMap()
    backend.failWeek = 2
    assertTrue(repo.update().isFailure)
    assertEquals(before, storage)
    backend.failWeek = null
    backend.onWeek = { throw CancellationException() }
    assertFailsWith<CancellationException> { repo.update() }
    assertEquals(before, storage)
    backend.onWeek = { account = "B" }
    assertTrue(repo.update().isFailure)
    assertEquals(before, storage)
  }

  @Test
  fun `semester switching keeps past imports and does not revive old courses on empty days`() =
      runTest {
        val storage = mutableMapOf<String, List<SemesterSchedule>>()
        val backend = Backend()
        val repo =
            ScheduleRepository(
                ScheduleApi { backend },
                { "A" },
                { storage[it].orEmpty() },
                { key, value -> storage[key] = value },
                { LocalDate.parse("2026-09-14") },
            )
        repo.update().getOrThrow()
        backend.term = Term("20262", "下一学期", true, 0)
        backend.start = "2026-09-14"
        backend.empty = true
        repo.update().getOrThrow()
        assertEquals(setOf("20261", "20262"), repo.terms().getOrThrow().map { it.itemCode }.toSet())
        assertTrue(repo.todayClasses().getOrThrow().isEmpty())
        val calls = backend.calls
        assertEquals("B课", repo.weekly("20261", 2).getOrThrow().arrangedList.single().courseName)
        assertTrue(repo.weekly("20262", 1).getOrThrow().arrangedList.isEmpty())
        assertEquals(calls, backend.calls)
      }

  private class Backend : ScheduleApiBackend {
    var calls = 0
    var fail = false
    var failWeek: Int? = null
    var onWeek: () -> Unit = {}
    var term = Term("20261", "示例学期", true, 0)
    var start = "2026-09-07"
    var empty = false

    override suspend fun getTerms(): Result<List<Term>> {
      calls++
      return if (fail) Result.failure(IllegalStateException("offline"))
      else Result.success(listOf(term))
    }

    override suspend fun getWeeks(termCode: String): Result<List<Week>> {
      calls++
      val first = LocalDate.parse(start).toEpochDays()
      return Result.success(
          (1..2).map {
            Week(
                LocalDate.fromEpochDays(first + (it - 1) * 7).toString(),
                LocalDate.fromEpochDays(first + (it - 1) * 7 + 6).toString(),
                termCode,
                false,
                it,
                "第${it}周",
            )
          }
      )
    }

    override suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> {
      calls++
      onWeek()
      if (failWeek == week) return Result.failure(IllegalStateException("timeout"))
      val course =
          CourseClass(
              "example",
              if (week == 1) "A课" else "B课",
              null,
              null,
              "08:00",
              "09:00",
              1,
              2,
              "教室",
              null,
              null,
              null,
              1,
          )
      return Result.success(
          WeeklySchedule(if (empty) emptyList() else listOf(course), termCode, term.itemName)
      )
    }

    override suspend fun getTodaySchedule(): Result<List<TodayClass>> = error("不得联网查询今日课表")

    override suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData> =
        error("unused")
  }
}
