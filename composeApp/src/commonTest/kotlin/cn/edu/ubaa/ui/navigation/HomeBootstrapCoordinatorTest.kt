package cn.edu.ubaa.ui.navigation

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

@OptIn(ExperimentalCoroutinesApi::class)
class HomeBootstrapCoordinatorTest {

  @Test
  fun restartStartsHomeBootstrapSourcesConcurrently() = runTest {
    val events = mutableListOf<String>()
    val coordinator = HomeBootstrapCoordinator(this)

    coordinator.restart(delayedActionsFor(events) { testScheduler.currentTime })
    runCurrent()

    assertEquals(
        listOf(
            "schedule:start:false@0",
            "signin:start:false@0",
            "spoc:start:false@0",
            "judge:start:false@0",
            "bykc:start:false@0",
            "cgyy:start:false@0",
            "ygdk:start:false@0",
        ),
        events,
    )
    assertTrue(coordinator.isRunning.value)

    advanceTimeBy(100)
    runCurrent()

    assertEquals(
        listOf(
            "schedule:start:false@0",
            "signin:start:false@0",
            "spoc:start:false@0",
            "judge:start:false@0",
            "bykc:start:false@0",
            "cgyy:start:false@0",
            "ygdk:start:false@0",
            "schedule:end:false@100",
            "signin:end:false@100",
            "spoc:end:false@100",
            "judge:end:false@100",
            "bykc:end:false@100",
            "cgyy:end:false@100",
            "ygdk:end:false@100",
        ),
        events,
    )
    assertFalse(coordinator.isRunning.value)
  }

  @Test
  fun restartCancelsPendingRunBeforeItStarts() = runTest {
    val events = mutableListOf<String>()
    val coordinator = HomeBootstrapCoordinator(this)

    coordinator.restart(actionsFor(events) { testScheduler.currentTime })
    coordinator.restart(actionsFor(events) { testScheduler.currentTime }, forceRefresh = true)
    runCurrent()

    assertEquals(
        listOf(
            "schedule:true@0",
            "signin:true@0",
            "spoc:true@0",
            "judge:true@0",
            "bykc:true@0",
            "cgyy:true@0",
            "ygdk:true@0",
        ),
        events,
    )
    assertFalse(coordinator.isRunning.value)
  }

  @Test
  fun cancelStopsPendingRunBeforeLoadsExecute() = runTest {
    val events = mutableListOf<String>()
    val coordinator = HomeBootstrapCoordinator(this)

    coordinator.restart(actionsFor(events) { testScheduler.currentTime })
    coordinator.cancel()
    advanceUntilIdle()

    assertEquals(emptyList(), events)
    assertFalse(coordinator.isRunning.value)
  }

  @Test
  fun restartClearsRunningWhenFirstStageThrows() = runTest {
    val failures = mutableListOf<Throwable>()
    val exceptionHandler = CoroutineExceptionHandler { _, throwable -> failures += throwable }
    val coordinator =
        HomeBootstrapCoordinator(
            CoroutineScope(coroutineContext + SupervisorJob() + exceptionHandler)
        )
    val actions =
        HomeBootstrapActions(
            loadTodaySchedule = { throw IllegalStateException("boom") },
            loadSignin = {},
            loadSpoc = {},
            loadJudge = {},
            loadBykc = {},
            loadCgyy = {},
            loadYgdk = {},
        )

    coordinator.restart(actions)

    assertTrue(coordinator.isRunning.value)
    runCurrent()
    assertFalse(coordinator.isRunning.value)
    assertEquals(listOf("boom"), failures.map { it.message })
  }

  private fun actionsFor(
      events: MutableList<String>,
      currentTime: () -> Long,
  ): HomeBootstrapActions {
    return HomeBootstrapActions(
        loadTodaySchedule = { force -> events += "schedule:$force@${currentTime()}" },
        loadSignin = { force -> events += "signin:$force@${currentTime()}" },
        loadSpoc = { force -> events += "spoc:$force@${currentTime()}" },
        loadJudge = { force -> events += "judge:$force@${currentTime()}" },
        loadBykc = { force -> events += "bykc:$force@${currentTime()}" },
        loadCgyy = { force -> events += "cgyy:$force@${currentTime()}" },
        loadYgdk = { force -> events += "ygdk:$force@${currentTime()}" },
    )
  }

  private fun delayedActionsFor(
      events: MutableList<String>,
      currentTime: () -> Long,
  ): HomeBootstrapActions {
    suspend fun record(source: String, force: Boolean) {
      events += "$source:start:$force@${currentTime()}"
      delay(100)
      events += "$source:end:$force@${currentTime()}"
    }

    return HomeBootstrapActions(
        loadTodaySchedule = { force -> record("schedule", force) },
        loadSignin = { force -> record("signin", force) },
        loadSpoc = { force -> record("spoc", force) },
        loadJudge = { force -> record("judge", force) },
        loadBykc = { force -> record("bykc", force) },
        loadCgyy = { force -> record("cgyy", force) },
        loadYgdk = { force -> record("ygdk", force) },
    )
  }
}
