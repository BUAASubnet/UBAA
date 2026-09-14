package cn.edu.ubaa.ui

import cn.edu.ubaa.api.auth.ApiCallException
import cn.edu.ubaa.api.feature.GraduateScheduleLoadException
import cn.edu.ubaa.api.feature.ScheduleApi
import cn.edu.ubaa.api.feature.ScheduleApiBackend
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.repository.ScheduleRepository
import cn.edu.ubaa.repository.SemesterSchedule
import cn.edu.ubaa.ui.screens.schedule.ScheduleViewModel
import kotlin.test.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import kotlinx.datetime.LocalDate

@OptIn(ExperimentalCoroutinesApi::class)
class ScheduleViewModelTest {
  @AfterTest
  fun cleanup() {
    Dispatchers.resetMain()
  }

  @Test
  fun `first visit loads online and only manual localization writes a complete semester`() =
      runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val f = Fixture()
        val model = f.model()
        model.ensureTodayLoaded()
        model.ensureCurrentWeekLoaded()
        model.ensureScheduleLoaded()
        advanceUntilIdle()
        assertEquals("在线课程", model.todayScheduleState.value.todayClasses.single().bizName)
        assertEquals(1, model.uiState.value.currentWeek?.serialNumber)
        assertEquals("1", model.uiState.value.weeklySchedule?.code)
        assertEquals(listOf(1), f.weekRequests)
        assertNull(model.uiState.value.error)
        assertTrue(f.saved.isEmpty())
        model.selectWeek(model.uiState.value.weeks[1])
        advanceUntilIdle()
        assertEquals("2", model.uiState.value.weeklySchedule?.code)
        assertEquals(listOf(1, 2), f.weekRequests)
        model.selectTerm(f.previous)
        advanceUntilIdle()
        assertEquals(f.previous.itemName, model.uiState.value.weeklySchedule?.name)
        assertTrue(f.saved.isEmpty())
        model.selectTerm(f.current)
        advanceUntilIdle()
        model.updateSchedule()
        model.updateSchedule()
        advanceUntilIdle()
        assertEquals(1, f.writes)
        assertEquals(setOf(1, 2), f.saved.single().schedules.keys)
        assertNotNull(model.uiState.value.updatedAt)
        assertFalse(model.uiState.value.isUpdating)
      }

  @Test
  fun `online refresh replaces memory data without overwriting localized snapshot`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val f = Fixture()
    f.repo.update().getOrThrow()
    val saved = f.saved
    val model = f.model()
    model.ensureScheduleLoaded()
    advanceUntilIdle()
    f.suffix = "新版"
    model.ensureScheduleLoaded(forceRefresh = true)
    advanceUntilIdle()
    assertEquals("1新版", model.uiState.value.weeklySchedule?.code)
    assertEquals(saved, f.saved)
    assertEquals(1, f.writes)
  }

  @Test
  fun `offline entry never calls online endpoints or localizes`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val f = Fixture()
    f.repo.update().getOrThrow()
    val calls = f.calls
    f.fail = true
    val model = f.model(offlineOnly = true)
    model.ensureTodayLoaded(forceRefresh = true)
    model.ensureCurrentWeekLoaded(forceRefresh = true)
    model.ensureScheduleLoaded(forceRefresh = true)
    model.selectWeek(model.uiState.value.weeks[1])
    model.updateSchedule()
    advanceUntilIdle()
    assertEquals(calls, f.calls)
    assertEquals("2", model.uiState.value.weeklySchedule?.code)
    assertNull(model.uiState.value.error)
  }

  @Test
  fun `network failure uses saved data and failed localization retains it`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val f = Fixture()
    f.repo.update().getOrThrow()
    val saved = f.saved
    f.fail = true
    val model = f.model()
    model.ensureTodayLoaded()
    model.ensureCurrentWeekLoaded()
    model.ensureScheduleLoaded()
    advanceUntilIdle()
    val visible = model.uiState.value.weeklySchedule
    assertNotNull(visible)
    assertNull(model.todayScheduleState.value.error)
    model.updateSchedule()
    advanceUntilIdle()
    assertEquals(saved, f.saved)
    assertEquals(visible, model.uiState.value.weeklySchedule)
    assertEquals("{test-response", model.uiState.value.diagnosticResponse)
    assertTrue(model.uiState.value.error!!.startsWith("本地化失败"))
    assertFalse(model.uiState.value.isUpdating)
  }

  @Test
  fun `first visit network failure preserves error and can retry without force`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val f = Fixture()
    f.fail = true
    val model = f.model()
    model.ensureTodayLoaded()
    model.ensureScheduleLoaded()
    advanceUntilIdle()
    assertEquals("解析失败", model.todayScheduleState.value.error)
    assertEquals("解析失败", model.uiState.value.error)
    assertFalse(model.hasTodayLoaded())
    assertFalse(model.uiState.value.isLoading)
    f.fail = false
    model.ensureTodayLoaded()
    model.ensureScheduleLoaded()
    advanceUntilIdle()
    assertNull(model.todayScheduleState.value.error)
    assertNull(model.uiState.value.error)
    assertTrue(model.hasTodayLoaded())
    assertTrue(f.saved.isEmpty())
  }

  @Test
  fun `late week response and reset cannot restore old selection or save pending import`() =
      runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val f = Fixture()
        val model = f.model()
        model.ensureScheduleLoaded()
        advanceUntilIdle()
        val pending = CompletableDeferred<Unit>()
        f.weekGate = pending
        model.selectWeek(model.uiState.value.weeks[1])
        model.selectWeek(model.uiState.value.weeks[0])
        pending.complete(Unit)
        advanceUntilIdle()
        assertEquals(1, model.uiState.value.selectedWeek?.serialNumber)
        assertEquals("1", model.uiState.value.weeklySchedule?.code)
        f.weekGate = CompletableDeferred()
        model.updateSchedule()
        runCurrent()
        model.resetLoadedState()
        f.weekGate!!.complete(Unit)
        advanceUntilIdle()
        assertTrue(f.saved.isEmpty())
        assertNull(model.uiState.value.selectedTerm)
        assertFalse(model.uiState.value.isUpdating)
        assertFalse(model.uiState.value.isLoading)
      }

  private class Fixture : ScheduleApiBackend {
    val current = Term("20261", "当前学期", true, 0)
    val previous = Term("20252", "历史学期", false, 1)
    var saved = emptyList<SemesterSchedule>()
    var writes = 0
    var calls = 0
    var fail = false
    var suffix = ""
    var weekGate: CompletableDeferred<Unit>? = null
    val weekRequests = mutableListOf<Int>()
    val repo =
        ScheduleRepository(
            ScheduleApi { this },
            { "A" },
            { saved },
            { _, value ->
              saved = value
              writes++
            },
            { LocalDate.parse("2026-09-07") },
        )

    fun model(offlineOnly: Boolean = false) =
        ScheduleViewModel(repository = repo, offlineOnly = offlineOnly)

    private fun <T> response(value: T): Result<T> {
      calls++
      return if (fail)
          Result.failure(
              ApiCallException(
                  "解析失败",
                  cause = GraduateScheduleLoadException("解析失败", "{test-response"),
              )
          )
      else Result.success(value)
    }

    override suspend fun getTerms() = response(listOf(current, previous))

    override suspend fun getWeeks(termCode: String) =
        response(
            listOf(
                Week("2026-09-07", "2026-09-13", termCode, true, 1, "第1周"),
                Week("2026-09-14", "2026-09-20", termCode, false, 2, "第2周"),
            )
        )

    override suspend fun getWeeklySchedule(termCode: String, week: Int): Result<WeeklySchedule> {
      weekRequests += week
      weekGate?.await()
      return response(
          WeeklySchedule(
              emptyList(),
              "$week$suffix",
              if (termCode == current.itemCode) current.itemName else previous.itemName,
          )
      )
    }

    override suspend fun getTodaySchedule() = response(listOf(TodayClass("在线课程", null, null, null)))

    override suspend fun getExamArrangement(termCode: String): Result<ExamArrangementData> =
        error("unused")
  }
}
