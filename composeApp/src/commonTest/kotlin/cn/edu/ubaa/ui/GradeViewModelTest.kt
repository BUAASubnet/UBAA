package cn.edu.ubaa.ui

import cn.edu.ubaa.model.dto.Grade
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.ui.screens.grade.GradeDataSource
import cn.edu.ubaa.ui.screens.grade.GradeTermsSource
import cn.edu.ubaa.ui.screens.grade.GradeViewModel
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain

@OptIn(ExperimentalCoroutinesApi::class)
class GradeViewModelTest {
  @AfterTest
  fun tearDown() {
    Dispatchers.resetMain()
  }

  @Test
  fun `force refresh keeps existing grades visible and exposes refresh state`() = runTest {
    setMainDispatcher(testScheduler)
    val termsSource = FakeGradeTermsSource(listOf(sampleTerm()))
    val gradeSource =
        FakeGradeDataSource(
            mutableMapOf(
                "2025-2026-1" to
                    mutableListOf(
                        GradeData(
                            termCode = "2025-2026-1",
                            grades = listOf(Grade(courseName = "高等数学", score = "90")),
                        ),
                        GradeData(
                            termCode = "2025-2026-1",
                            grades = listOf(Grade(courseName = "高等数学", score = "95")),
                        ),
                    )
            )
        )
    val viewModel = GradeViewModel(gradeSource = gradeSource, termsSource = termsSource)

    viewModel.ensureLoaded()
    advanceUntilIdle()

    assertEquals("90", viewModel.uiState.value.gradeData?.grades?.singleOrNull()?.score)

    viewModel.ensureLoaded(forceRefresh = true)
    runCurrent()

    assertFalse(viewModel.uiState.value.isLoading)
    assertTrue(viewModel.uiState.value.isRefreshing)
    assertEquals("90", viewModel.uiState.value.gradeData?.grades?.singleOrNull()?.score)

    advanceUntilIdle()

    assertFalse(viewModel.uiState.value.isRefreshing)
    assertEquals("95", viewModel.uiState.value.gradeData?.grades?.singleOrNull()?.score)
    assertEquals(listOf(false, true), termsSource.forceRefreshRequests)
  }

  @Test
  fun `loads all term grades concurrently`() = runTest {
    setMainDispatcher(testScheduler)
    val terms =
        listOf(
            sampleTerm("2025-2026-1", selected = true),
            sampleTerm("2024-2025-2"),
            sampleTerm("2024-2025-1"),
        )
    val gradeSource = ConcurrentTrackingGradeDataSource(terms.map { it.itemCode }.toSet())
    val viewModel =
        GradeViewModel(gradeSource = gradeSource, termsSource = FakeGradeTermsSource(terms))

    viewModel.ensureLoaded()
    runCurrent()

    assertEquals(3, gradeSource.maxConcurrentRequests)

    advanceUntilIdle()

    assertEquals(terms.map { it.itemCode }.toSet(), viewModel.uiState.value.termGrades.keys)
    assertFalse(viewModel.uiState.value.isSummaryLoading)
  }

  private fun setMainDispatcher(testScheduler: TestCoroutineScheduler) {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
  }
}

private class FakeGradeTermsSource(private val terms: List<Term>) : GradeTermsSource {
  val forceRefreshRequests = mutableListOf<Boolean>()

  override suspend fun getTerms(forceRefresh: Boolean): Result<List<Term>> {
    forceRefreshRequests += forceRefresh
    return Result.success(terms)
  }
}

private class FakeGradeDataSource(
    private val gradeDataByTerm: MutableMap<String, MutableList<GradeData>>
) : GradeDataSource {
  override suspend fun getGrades(termCode: String): Result<GradeData> {
    delay(100)
    val queue = gradeDataByTerm.getValue(termCode)
    return Result.success(queue.removeAt(0))
  }
}

private class ConcurrentTrackingGradeDataSource(private val expectedTermCodes: Set<String>) :
    GradeDataSource {
  private var activeRequests = 0
  var maxConcurrentRequests = 0
    private set

  override suspend fun getGrades(termCode: String): Result<GradeData> {
    require(termCode in expectedTermCodes)
    activeRequests += 1
    maxConcurrentRequests = maxOf(maxConcurrentRequests, activeRequests)
    delay(100)
    activeRequests -= 1
    return Result.success(GradeData(termCode = termCode, grades = emptyList()))
  }
}

private fun sampleTerm(
    itemCode: String = "2025-2026-1",
    selected: Boolean = true,
): Term =
    Term(
        itemCode = itemCode,
        itemName = itemCode,
        selected = selected,
        itemIndex = 0,
    )
