package cn.edu.ubaa.ui

import cn.edu.ubaa.api.feature.IhomeApi
import cn.edu.ubaa.model.dto.*
import cn.edu.ubaa.ui.screens.ihome.*
import kotlin.test.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*

@OptIn(ExperimentalCoroutinesApi::class)
class IhomeViewModelTest {
  @AfterTest
  fun cleanup() {
    Dispatchers.resetMain()
  }

  @Test
  fun `重复页停止加载且不会重复追加`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val api = FakeIhomeApi()
    api.page = { Result.success(IhomePage(listOf(IhomeEntry(appeal(1))), 1, 2, 2)) }
    val vm = IhomeViewModel(api)
    vm.ensureLoaded()
    advanceUntilIdle()
    assertTrue(vm.uiState.value.hasMore)
    vm.loadMore()
    advanceUntilIdle()
    assertEquals(1, vm.uiState.value.entries.size)
    assertFalse(vm.uiState.value.hasMore)
  }

  @Test
  fun `搜索始终走公共接口且旧筛选不残留`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val api = FakeIhomeApi()
    val vm = IhomeViewModel(api)
    vm.selectView(IhomeView.MINE)
    advanceUntilIdle()
    vm.search("校园")
    advanceUntilIdle()
    assertEquals(IhomeScope.PUBLIC, api.queries.last().scope)
    assertEquals("校园", api.queries.last().keyword)
    vm.filter(IhomeFilter.ALL, 4)
    advanceUntilIdle()
    vm.filter(IhomeFilter.REPLIED)
    advanceUntilIdle()
    assertNull(api.queries.last().categoryId)
  }

  @Test
  fun `重置会话后旧请求不能恢复个人数据`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val api = FakeIhomeApi()
    val response = CompletableDeferred<Result<IhomePage>>()
    api.page = { withContext(NonCancellable) { response.await() } }
    val vm = IhomeViewModel(api)
    vm.ensureLoaded()
    runCurrent()
    vm.resetLoadedState()
    response.complete(Result.success(IhomePage(listOf(IhomeEntry(appeal(1))), 1, 1, 1)))
    advanceUntilIdle()
    assertTrue(vm.uiState.value.entries.isEmpty())
    assertFalse(vm.uiState.value.loading)
  }

  @Test
  fun `操作未确认时阻止再次切换并允许详情回查恢复`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val api = FakeIhomeApi()
    api.reaction = { Result.success(IhomeReactionResult(message = "未确认")) }
    val vm = IhomeViewModel(api)
    val item = appeal(1)
    vm.react(item, IhomeReaction.FOLLOW)
    vm.react(item, IhomeReaction.FOLLOW)
    advanceUntilIdle()
    vm.react(item, IhomeReaction.FOLLOW)
    advanceUntilIdle()
    assertEquals(1, api.writes)
    assertTrue(1L in vm.uiState.value.uncertain)
    vm.openDetail(1)
    advanceUntilIdle()
    assertTrue(vm.uiState.value.uncertain.isEmpty())
  }

  @Test
  fun `取消关注后从我的关注移除条目`() = runTest {
    Dispatchers.setMain(StandardTestDispatcher(testScheduler))
    val api = FakeIhomeApi()
    val item = appeal(1).copy(isFollowed = true)
    api.page = { Result.success(IhomePage(listOf(IhomeEntry(item)), 1, 1, 1)) }
    api.reaction = { Result.success(IhomeReactionResult(item.copy(isFollowed = false), true)) }
    val vm = IhomeViewModel(api)
    vm.selectView(IhomeView.FOLLOWED)
    advanceUntilIdle()
    vm.react(item, IhomeReaction.FOLLOW)
    advanceUntilIdle()
    assertTrue(vm.uiState.value.entries.isEmpty())
  }

  private fun appeal(id: Long) = IhomeAppeal(id, "测试诉求", isFollowed = false, isSupported = false)

  private inner class FakeIhomeApi : IhomeApi() {
    val queries = mutableListOf<IhomeQuery>()
    var writes = 0
    var page: suspend (IhomeQuery) -> Result<IhomePage> = {
      Result.success(IhomePage(emptyList(), 1, 1, 0))
    }
    var reaction: suspend (IhomeReactionRequest) -> Result<IhomeReactionResult> = {
      Result.success(IhomeReactionResult())
    }

    override suspend fun getPage(query: IhomeQuery): Result<IhomePage> {
      queries += query
      return page(query)
    }

    override suspend fun getConfig() = Result.success(IhomeConfig(true))

    override suspend fun getDetail(id: Long, mine: Boolean) = Result.success(appeal(id))

    override suspend fun setReaction(
        id: Long,
        request: IhomeReactionRequest,
    ): Result<IhomeReactionResult> {
      writes++
      return reaction(request)
    }
  }
}
