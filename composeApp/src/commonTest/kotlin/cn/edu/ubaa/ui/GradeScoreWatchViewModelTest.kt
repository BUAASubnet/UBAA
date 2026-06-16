package cn.edu.ubaa.ui

import cn.edu.ubaa.api.storage.StoredGradeScoreCache
import cn.edu.ubaa.api.storage.StoredGradeScoreEntry
import cn.edu.ubaa.model.dto.Grade
import cn.edu.ubaa.model.dto.GradeData
import cn.edu.ubaa.model.dto.Term
import cn.edu.ubaa.ui.screens.grade.GradeDataSource
import cn.edu.ubaa.ui.screens.grade.GradeScoreCache
import cn.edu.ubaa.ui.screens.grade.GradeScoreWatchViewModel
import cn.edu.ubaa.ui.screens.grade.GradeTermsSource
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestCoroutineScheduler
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain

@OptIn(ExperimentalCoroutinesApi::class)
class GradeScoreWatchViewModelTest {
  @AfterTest
  fun tearDown() {
    Dispatchers.resetMain()
  }

  @Test
  fun `first non-empty current term seeds cache without notice`() = runTest {
    setMainDispatcher(testScheduler)
    val cache = FakeGradeScoreCache()
    val viewModel =
        GradeScoreWatchViewModel(
            userKey = "test-user",
            termsSource = FakeScoreWatchTermsSource(listOf(sampleTerm())),
            gradeSource = FakeScoreWatchDataSource("2025-2026-1" to grades("高等数学", "90")),
            cache = cache,
        )

    viewModel.ensureChecked()
    advanceUntilIdle()

    assertNull(viewModel.uiState.value.notice)
    assertEquals("90", cache.get("test-user")?.scores?.singleOrNull()?.score)
    assertTrue(viewModel.hasChecked())
  }

  @Test
  fun `same scores update cache without notice`() = runTest {
    setMainDispatcher(testScheduler)
    val cache =
        FakeGradeScoreCache(
            mapOf("test-user" to cached("2025-2026-1", score = "90", courseName = "高等数学"))
        )
    val viewModel =
        GradeScoreWatchViewModel(
            userKey = "test-user",
            termsSource = FakeScoreWatchTermsSource(listOf(sampleTerm())),
            gradeSource = FakeScoreWatchDataSource("2025-2026-1" to grades("高等数学", "90")),
            cache = cache,
        )

    viewModel.ensureChecked()
    advanceUntilIdle()

    assertNull(viewModel.uiState.value.notice)
    assertEquals("90", cache.get("test-user")?.scores?.singleOrNull()?.score)
  }

  @Test
  fun `changed score updates cache and emits notice`() = runTest {
    setMainDispatcher(testScheduler)
    val cache =
        FakeGradeScoreCache(
            mapOf("test-user" to cached("2025-2026-1", score = "90", courseName = "高等数学"))
        )
    val viewModel =
        GradeScoreWatchViewModel(
            userKey = "test-user",
            termsSource = FakeScoreWatchTermsSource(listOf(sampleTerm())),
            gradeSource = FakeScoreWatchDataSource("2025-2026-1" to grades("高等数学", "95")),
            cache = cache,
        )

    viewModel.ensureChecked()
    advanceUntilIdle()

    val notice = viewModel.uiState.value.notice
    assertEquals("2025-2026学年第一学期", notice?.termName)
    assertEquals(1, notice?.changedCount)
    assertEquals("高等数学", notice?.changedScores?.singleOrNull()?.courseName)
    assertEquals("90", notice?.changedScores?.singleOrNull()?.oldScore)
    assertEquals("95", notice?.changedScores?.singleOrNull()?.newScore)
    assertEquals("95", cache.get("test-user")?.scores?.singleOrNull()?.score)
  }

  @Test
  fun `empty current term is ignored and does not overwrite cache`() = runTest {
    setMainDispatcher(testScheduler)
    val cache =
        FakeGradeScoreCache(
            mapOf("test-user" to cached("2025-2026-1", score = "90", courseName = "高等数学"))
        )
    val viewModel =
        GradeScoreWatchViewModel(
            userKey = "test-user",
            termsSource = FakeScoreWatchTermsSource(listOf(sampleTerm())),
            gradeSource = FakeScoreWatchDataSource("2025-2026-1" to GradeData("2025-2026-1")),
            cache = cache,
        )

    viewModel.ensureChecked()
    advanceUntilIdle()

    assertNull(viewModel.uiState.value.notice)
    assertEquals("90", cache.get("test-user")?.scores?.singleOrNull()?.score)
  }

  @Test
  fun `only selected current term is watched`() = runTest {
    setMainDispatcher(testScheduler)
    val cache = FakeGradeScoreCache()
    val terms =
        listOf(
            sampleTerm("2025-2026-1", selected = true),
            sampleTerm("2024-2025-2", selected = false),
        )
    val gradeSource =
        FakeScoreWatchDataSource(
            "2025-2026-1" to grades("高等数学", "90"),
            "2024-2025-2" to grades("大学物理", "95"),
        )
    val viewModel =
        GradeScoreWatchViewModel(
            userKey = "test-user",
            termsSource = FakeScoreWatchTermsSource(terms),
            gradeSource = gradeSource,
            cache = cache,
        )

    viewModel.ensureChecked()
    advanceUntilIdle()

    assertEquals(listOf("2025-2026-1"), gradeSource.requestedTerms)
    assertEquals("2025-2026-1", cache.get("test-user")?.termCode)
  }

  private fun setMainDispatcher(testScheduler: TestCoroutineScheduler) {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
  }
}

private class FakeGradeScoreCache(initial: Map<String, StoredGradeScoreCache> = emptyMap()) :
    GradeScoreCache {
  private val data = initial.toMutableMap()

  override fun get(userKey: String): StoredGradeScoreCache? = data[userKey]

  override fun save(userKey: String, cache: StoredGradeScoreCache) {
    data[userKey] = cache
  }
}

private class FakeScoreWatchTermsSource(private val terms: List<Term>) : GradeTermsSource {
  override suspend fun getTerms(forceRefresh: Boolean): Result<List<Term>> = Result.success(terms)
}

private class FakeScoreWatchDataSource(private vararg val data: Pair<String, GradeData>) :
    GradeDataSource {
  val requestedTerms = mutableListOf<String>()
  private val dataByTerm = data.toMap()

  override suspend fun getGrades(termCode: String): Result<GradeData> {
    requestedTerms += termCode
    return Result.success(dataByTerm.getValue(termCode))
  }
}

private fun grades(courseName: String, score: String): GradeData =
    GradeData(
        termCode = "2025-2026-1",
        grades =
            listOf(
                Grade(
                    id = "grade-$courseName",
                    termCode = "2025-2026-1",
                    courseName = courseName,
                    courseCode = courseName,
                    score = score,
                )
            ),
    )

private fun cached(
    termCode: String,
    score: String,
    courseName: String,
): StoredGradeScoreCache =
    StoredGradeScoreCache(
        termCode = termCode,
        termName = "2025-2026学年第一学期",
        scores =
            listOf(
                StoredGradeScoreEntry(
                    key = "id:grade-$courseName",
                    courseName = courseName,
                    courseCode = courseName,
                    score = score,
                )
            ),
    )

private fun sampleTerm(
    itemCode: String = "2025-2026-1",
    selected: Boolean = true,
): Term =
    Term(
        itemCode = itemCode,
        itemName =
            if (itemCode == "2025-2026-1") {
              "2025-2026学年第一学期"
            } else {
              itemCode
            },
        selected = selected,
        itemIndex = 0,
    )
