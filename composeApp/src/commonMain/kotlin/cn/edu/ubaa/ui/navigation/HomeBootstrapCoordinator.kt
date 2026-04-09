package cn.edu.ubaa.ui.navigation

import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.yield

internal data class HomeBootstrapActions(
    val loadTodaySchedule: (Boolean) -> Unit,
    val loadSignin: (Boolean) -> Unit,
    val loadSpoc: (Boolean) -> Unit,
    val loadBykc: (Boolean) -> Unit,
    val loadCgyy: (Boolean) -> Unit,
)

internal class HomeBootstrapCoordinator(private val scope: CoroutineScope) {
  private val _isRunning = MutableStateFlow(false)
  val isRunning: StateFlow<Boolean> = _isRunning.asStateFlow()

  private var job: Job? = null

  fun restart(
      actions: HomeBootstrapActions,
      forceRefresh: Boolean = false,
      showLoading: Boolean = true,
  ) {
    val previous = job
    previous?.cancel()

    val newJob =
        scope.launch(start = CoroutineStart.LAZY) {
          try {
            actions.loadTodaySchedule(forceRefresh)
            actions.loadSignin(forceRefresh)
            actions.loadSpoc(forceRefresh)
            actions.loadBykc(forceRefresh)
            actions.loadCgyy(forceRefresh)
            yield()
          } finally {
            if (job === coroutineContext[Job]) {
              job = null
              _isRunning.value = false
            }
          }
        }

    job = newJob
    _isRunning.value = showLoading
    newJob.start()
  }

  fun cancel() {
    val current = job ?: return
    job = null
    _isRunning.value = false
    current.cancel()
  }
}
