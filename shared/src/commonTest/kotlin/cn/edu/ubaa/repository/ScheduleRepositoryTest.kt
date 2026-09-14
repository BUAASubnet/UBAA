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

  @Test
  fun `localization accepts opaque weekly codes but rejects incomplete or mismatched snapshots`() =
      runTest {
        val backend = Backend()
        val good =
            backend.importSemester(null).getOrThrow().let { snapshot ->
              snapshot.copy(
                  schedules =
                      snapshot.schedules.mapValues { (week, schedule) ->
                        schedule.copy(code = week.toString(), name = "上游周课表")
                      }
              )
            }
        var incoming = good
        var saved = emptyList<SemesterSchedule>()
        val importer =
            object : ScheduleApiBackend by backend {
              override suspend fun importSemester(termCode: String?) = Result.success(incoming)
            }
        val repo =
            ScheduleRepository(
                ScheduleApi { importer },
                { "A" },
                { saved },
                { _, value -> saved = value },
            )
        repo.update(good.termCode).getOrThrow()
        val before = saved
        assertEquals("1", saved.single().schedules[1]?.code)
        val invalid =
            listOf(
                good.copy(schedules = good.schedules - 2),
                good.copy(weeks = good.weeks + good.weeks.first()),
                good.copy(weeks = good.weeks.map { it.copy(term = "other-term") }),
                good.copy(weeks = good.weeks.map { it.copy(startDate = "2026-10-01") }),
                good.copy(termCode = "other-term"),
            )
        for (snapshot in invalid) {
          incoming = snapshot
          assertTrue(repo.update(good.termCode).isFailure)
          assertEquals(before, saved)
        }
      }

  @Test
  fun `online browsing never writes and original network failure survives missing local data`() =
      runTest {
        val backend = Backend()
        var writes = 0
        val repo =
            ScheduleRepository(
                ScheduleApi { backend },
                { "A" },
                { emptyList() },
                { _, _ -> writes++ },
            )
        assertEquals(backend.term, repo.loadTerms().getOrThrow().single())
        assertEquals(2, repo.loadWeeks(backend.term.itemCode).getOrThrow().size)
        assertEquals(
            "A课",
            repo.loadWeekly(backend.term.itemCode, 1).getOrThrow().arrangedList.single().courseName,
        )
        assertEquals(0, writes)
        backend.fail = true
        assertEquals("offline", repo.loadTerms().exceptionOrNull()?.message)
        val calls = backend.calls
        assertTrue(repo.loadTerms(offlineOnly = true).isFailure)
        assertEquals(calls, backend.calls)
      }

  @Test
  fun `account switch and cancellation cannot fall back to another account data`() = runTest {
    var account = "A"
    val backend = Backend()
    var localReads = 0
    val repo =
        ScheduleRepository(
            ScheduleApi { backend },
            { account },
            {
              localReads++
              emptyList()
            },
            { _, _ -> },
        )
    backend.onWeek = { account = "B" }
    assertTrue(repo.loadWeekly(backend.term.itemCode, 1).isFailure)
    assertEquals(0, localReads)
    backend.onWeek = { throw CancellationException() }
    assertFailsWith<CancellationException> { repo.loadWeekly(backend.term.itemCode, 1) }
    assertEquals(0, localReads)
  }

  @Test
  fun `undergraduate date time boundaries normalize before saving and include the first day offline`() =
      runTest {
        val backend = Backend()
        val raw =
            backend.importSemester(null).getOrThrow().let { snapshot ->
              snapshot.copy(
                  weeks =
                      snapshot.weeks.map {
                        it.copy(
                            startDate = it.startDate + " 00:00:00",
                            endDate = it.endDate + " 00:00:00",
                        )
                      }
              )
            }
        val importer =
            object : ScheduleApiBackend by backend {
              override suspend fun importSemester(termCode: String?) = Result.success(raw)

              override suspend fun getWeeks(termCode: String) = Result.success(raw.weeks)
            }
        var saved = emptyList<SemesterSchedule>()
        val repo =
            ScheduleRepository(
                ScheduleApi { importer },
                { "A" },
                { saved },
                { _, value -> saved = value },
                { LocalDate.parse("2026-09-14") },
            )
        assertEquals("2026-09-07", repo.loadWeeks(raw.termCode).getOrThrow().first().startDate)
        repo.update().getOrThrow()
        assertEquals("2026-09-20", saved.single().weeks.last().endDate)
        assertEquals(2, repo.weeks(raw.termCode).getOrThrow().single { it.curWeek }.serialNumber)
        assertEquals("B课", repo.loadTodayClasses(offlineOnly = true).getOrThrow().single().bizName)
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
