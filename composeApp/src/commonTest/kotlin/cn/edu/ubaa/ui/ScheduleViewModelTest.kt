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
  fun `home and schedule browsing are offline and failed manual update retains visible data`() =
      runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val current = Term("20261", "当前学期", true, 0)
        val previous = Term("20252", "历史学期", false, 1)
        val week = Week("2026-09-07", "2026-09-13", current.itemCode, false, 1, "第1周")
        val schedule = WeeklySchedule(emptyList(), current.itemCode, current.itemName)
        val saved =
            listOf(
                SemesterSchedule(
                    listOf(current, previous),
                    current.itemCode,
                    listOf(week),
                    mapOf(1 to schedule),
                    "2026-09-07 09:00",
                )
            )
        var calls = 0
        val backend =
            object : ScheduleApiBackend {
              override suspend fun getTerms(): Result<List<Term>> {
                calls++
                return Result.failure(
                    ApiCallException(
                        "解析失败",
                        cause = GraduateScheduleLoadException("解析失败", "{test-response"),
                    )
                )
              }

              override suspend fun getWeeks(termCode: String): Result<List<Week>> =
                  error("unexpected")

              override suspend fun getWeeklySchedule(
                  termCode: String,
                  week: Int,
              ): Result<WeeklySchedule> = error("unexpected")

              override suspend fun getTodaySchedule(): Result<List<TodayClass>> =
                  error("unexpected")

              override suspend fun getExamArrangement(
                  termCode: String
              ): Result<ExamArrangementData> = error("unexpected")
            }
        val repo =
            ScheduleRepository(
                ScheduleApi { backend },
                { "A" },
                { saved },
                { _, _ -> error("must not save failure") },
                { LocalDate.parse("2026-09-07") },
            )
        val model = ScheduleViewModel(repository = repo)
        model.ensureTodayLoaded(forceRefresh = true)
        model.ensureCurrentWeekLoaded(forceRefresh = true)
        model.ensureScheduleLoaded(forceRefresh = true)
        assertEquals(0, calls)
        assertEquals(schedule, model.uiState.value.weeklySchedule)
        assertEquals(1, model.uiState.value.currentWeek?.serialNumber)
        model.updateSchedule()
        model.updateSchedule() // 重复点击不重复请求。
        advanceUntilIdle()
        assertEquals(1, calls)
        assertEquals(schedule, model.uiState.value.weeklySchedule)
        assertEquals("2026-09-07 09:00", model.uiState.value.updatedAt)
        assertNotNull(model.uiState.value.error)
        assertEquals("{test-response", model.uiState.value.diagnosticResponse)
        assertFalse(model.uiState.value.isUpdating)
        model.selectTerm(previous)
        assertNull(model.uiState.value.diagnosticResponse)
        assertNull(model.uiState.value.weeklySchedule)
        assertNotNull(model.uiState.value.error)
        assertEquals(1, calls)
        model.selectTerm(current)
        assertEquals(schedule, model.uiState.value.weeklySchedule)
        assertNull(model.uiState.value.error)
      }
}
