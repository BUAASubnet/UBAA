package cn.edu.ubaa.ui.navigation

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

@OptIn(ExperimentalCoroutinesApi::class)
class HomeBootstrapCoordinatorTest {

  @Test
  fun restartRunsHomeBootstrapInStages() = runTest {
    val events = mutableListOf<String>()
    val coordinator = HomeBootstrapCoordinator(this)

    coordinator.restart(actionsFor(events) { testScheduler.currentTime })
    runCurrent()
    assertEquals(
        listOf(
            "schedule:false@0",
            "signin:false@0",
            "spoc:false@0",
            "bykc:false@0",
            "cgyy:false@0",
        ),
        events,
    )
    assertFalse(coordinator.isRunning.value)
  }

  @Test
  fun restartCancelsPendingStagesFromPreviousRun() = runTest {
    val events = mutableListOf<String>()
    val coordinator = HomeBootstrapCoordinator(this)

    coordinator.restart(actionsFor(events) { testScheduler.currentTime })
    runCurrent()
    advanceTimeBy(200)
    coordinator.restart(actionsFor(events) { testScheduler.currentTime }, forceRefresh = true)
    runCurrent()
    advanceUntilIdle()

    assertEquals(
        listOf(
            "schedule:false@0",
            "signin:false@0",
            "spoc:false@0",
            "bykc:false@0",
            "cgyy:false@0",
            "schedule:true@200",
            "signin:true@200",
            "spoc:true@200",
            "bykc:true@200",
            "cgyy:true@200",
        ),
        events,
    )
    assertFalse(coordinator.isRunning.value)
  }

  @Test
  fun cancelStopsPendingDelayedLoads() = runTest {
    val events = mutableListOf<String>()
    val coordinator = HomeBootstrapCoordinator(this)

    coordinator.restart(actionsFor(events) { testScheduler.currentTime })
    runCurrent()
    coordinator.cancel()
    advanceUntilIdle()

    assertEquals(
        listOf(
            "schedule:false@0",
            "signin:false@0",
            "spoc:false@0",
            "bykc:false@0",
            "cgyy:false@0",
        ),
        events,
    )
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
            loadCgyy = {},
            loadBykc = {},
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
        loadCgyy = { force -> events += "cgyy:$force@${currentTime()}" },
        loadBykc = { force -> events += "bykc:$force@${currentTime()}" },
    )
  }
}
