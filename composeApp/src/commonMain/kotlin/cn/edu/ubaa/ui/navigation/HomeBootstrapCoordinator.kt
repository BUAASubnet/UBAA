package cn.edu.ubaa.ui.navigation

import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.supervisorScope

internal data class HomeBootstrapActions(
    val loadTodaySchedule: suspend (Boolean) -> Unit,
    val loadSignin: suspend (Boolean) -> Unit,
    val loadSpoc: suspend (Boolean) -> Unit,
    val loadJudge: suspend (Boolean) -> Unit,
    val loadBykc: suspend (Boolean) -> Unit,
    val loadCgyy: suspend (Boolean) -> Unit,
    val loadYgdk: suspend (Boolean) -> Unit,
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
            supervisorScope {
              listOf(
                      launch { actions.loadTodaySchedule(forceRefresh) },
                      launch { actions.loadSignin(forceRefresh) },
                      launch { actions.loadSpoc(forceRefresh) },
                      launch { actions.loadJudge(forceRefresh) },
                      launch { actions.loadBykc(forceRefresh) },
                      launch { actions.loadCgyy(forceRefresh) },
                      launch { actions.loadYgdk(forceRefresh) },
                  )
                  .joinAll()
            }
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
