package cn.edu.ubaa.ui.screens.ihome

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.feature.IhomeApi
import cn.edu.ubaa.model.dto.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class IhomeView(val title: String, val scope: IhomeScope?) {
  PUBLIC("诉求广场", IhomeScope.PUBLIC),
  MINE("我的发起", IhomeScope.MINE),
  FOLLOWED("我的关注", IhomeScope.FOLLOWED),
  APPRAISED("我的评价", IhomeScope.APPRAISED),
  NOTICES("公告", null),
}

data class IhomeUiState(
    val view: IhomeView = IhomeView.PUBLIC,
    val query: IhomeQuery = IhomeQuery(),
    val entries: List<IhomeEntry> = emptyList(),
    val notices: List<IhomeNotice> = emptyList(),
    val config: IhomeConfig = IhomeConfig(),
    val configError: String? = null,
    val loading: Boolean = false,
    val hasMore: Boolean = false,
    val error: String? = null,
    val selectedId: Long? = null,
    val detailMine: Boolean = false,
    val detail: IhomeAppeal? = null,
    val notice: IhomeNotice? = null,
    val detailLoading: Boolean = false,
    val detailError: String? = null,
    val busy: Set<Long> = emptySet(),
    val uncertain: Set<Long> = emptySet(),
)

class IhomeViewModel(private val api: IhomeApi = IhomeApi()) : ViewModel() {
  private val state = MutableStateFlow(IhomeUiState())
  val uiState = state.asStateFlow()
  private var epoch = 0
  private var listVersion = 0
  private var detailVersion = 0
  private var loaded = false
  private var listJob: Job? = null
  private var detailJob: Job? = null

  fun resetLoadedState() {
    epoch++
    listVersion++
    detailVersion++
    listJob?.cancel()
    detailJob?.cancel()
    loaded = false
    state.value = IhomeUiState()
  }

  fun ensureLoaded() {
    if (loaded) return
    loaded = true
    loadConfig()
    refresh()
  }

  fun loadConfig() {
    val currentEpoch = epoch
    viewModelScope.launch {
      val result = api.getConfig()
      if (currentEpoch != epoch) return@launch
      result
          .onSuccess { state.value = state.value.copy(config = it, configError = null) }
          .onFailure { state.value = state.value.copy(configError = "平台设置加载失败") }
    }
  }

  fun selectView(view: IhomeView) {
    if (view == state.value.view) return
    closeDetail()
    state.value =
        state.value.copy(
            view = view,
            query =
                IhomeQuery(
                    scope = view.scope ?: IhomeScope.PUBLIC,
                    filter = if (view == IhomeView.MINE) IhomeFilter.NEWEST else IhomeFilter.ALL,
                ),
            entries = emptyList(),
            notices = emptyList(),
            error = null,
            hasMore = false,
        )
    refresh()
  }

  fun search(keyword: String) {
    closeDetail()
    state.value =
        state.value.copy(
            view = IhomeView.PUBLIC,
            query = IhomeQuery(keyword = keyword.trim().take(200)),
            entries = emptyList(),
        )
    refresh()
  }

  fun filter(filter: IhomeFilter, categoryId: Long? = null) {
    state.value =
        state.value.copy(
            query = state.value.query.copy(page = 1, filter = filter, categoryId = categoryId),
            entries = emptyList(),
        )
    refresh()
  }

  fun refresh() = loadPage(append = false)

  fun loadMore() {
    if (!state.value.loading && state.value.hasMore) loadPage(append = true)
  }

  private fun loadPage(append: Boolean) {
    listJob?.cancel()
    val version = ++listVersion
    val currentEpoch = epoch
    val initial = state.value
    val query = initial.query.copy(page = if (append) initial.query.page + 1 else 1)
    state.value = initial.copy(loading = true, error = null)
    listJob =
        viewModelScope.launch {
          if (initial.view == IhomeView.NOTICES) {
            val result = api.getNotices()
            if (currentEpoch != epoch || version != listVersion) return@launch
            result
                .onSuccess {
                  state.value = state.value.copy(notices = it, loading = false, hasMore = false)
                }
                .onFailure {
                  state.value = state.value.copy(loading = false, error = it.message ?: "公告加载失败")
                }
          } else {
            val result = api.getPage(query)
            if (currentEpoch != epoch || version != listVersion) return@launch
            result
                .onSuccess { page ->
                  val old = if (append) state.value.entries else emptyList()
                  fun IhomeEntry.key() = evaluation?.let { "评价:${it.id}" } ?: "诉求:${appeal.id}"
                  val existing = old.map { it.key() }.toSet()
                  val added = page.entries.filter { it.key() !in existing }.distinctBy { it.key() }
                  state.value =
                      state.value.copy(
                          entries = old + added,
                          query = query.copy(page = page.page),
                          loading = false,
                          hasMore =
                              page.page >= query.page &&
                                  page.page < page.lastPage &&
                                  added.isNotEmpty(),
                      )
                }
                .onFailure {
                  state.value = state.value.copy(loading = false, error = it.message ?: "诉求加载失败")
                }
          }
        }
  }

  fun openDetail(id: Long, mine: Boolean = state.value.view == IhomeView.MINE) {
    detailJob?.cancel()
    val version = ++detailVersion
    val currentEpoch = epoch
    state.value =
        state.value.copy(
            selectedId = id,
            detailMine = mine,
            detail = null,
            notice = null,
            detailLoading = true,
            detailError = null,
        )
    detailJob =
        viewModelScope.launch {
          val result = api.getDetail(id, mine)
          if (epoch != currentEpoch || detailVersion != version) return@launch
          result
              .onSuccess { appeal ->
                state.value =
                    state.value.copy(
                        detail = appeal,
                        detailLoading = false,
                        uncertain = state.value.uncertain - id,
                    )
                replaceAppeal(appeal)
              }
              .onFailure {
                state.value =
                    state.value.copy(detailLoading = false, detailError = it.message ?: "详情加载失败")
              }
        }
  }

  fun openNotice(id: Long) {
    detailJob?.cancel()
    val version = ++detailVersion
    val currentEpoch = epoch
    state.value =
        state.value.copy(
            selectedId = id,
            detail = null,
            notice = null,
            detailLoading = true,
            detailError = null,
        )
    detailJob =
        viewModelScope.launch {
          val result = api.getNotice(id)
          if (epoch != currentEpoch || detailVersion != version) return@launch
          result
              .onSuccess { state.value = state.value.copy(notice = it, detailLoading = false) }
              .onFailure {
                state.value =
                    state.value.copy(detailLoading = false, detailError = it.message ?: "公告加载失败")
              }
        }
  }

  fun retryDetail() {
    val id = state.value.selectedId ?: return
    if (state.value.view == IhomeView.NOTICES) openNotice(id)
    else openDetail(id, state.value.detailMine)
  }

  fun closeDetail() {
    detailVersion++
    detailJob?.cancel()
    state.value =
        state.value.copy(
            selectedId = null,
            detail = null,
            notice = null,
            detailLoading = false,
            detailError = null,
        )
  }

  fun react(appeal: IhomeAppeal, reaction: IhomeReaction) {
    val initial = state.value
    if (appeal.id in initial.busy || appeal.id in initial.uncertain) return
    val value =
        (if (reaction == IhomeReaction.FOLLOW) appeal.isFollowed else appeal.isSupported) ?: return
    if (reaction == IhomeReaction.SUPPORT && !initial.config.supportEnabled) return
    val currentEpoch = epoch
    // 使正在加载的旧列表/详情失效，避免回查后的状态被旧响应覆盖。
    listVersion++
    detailVersion++
    listJob?.cancel()
    detailJob?.cancel()
    state.value =
        initial.copy(
            busy = initial.busy + appeal.id,
            error = null,
            loading = false,
            detailLoading = false,
        )
    viewModelScope.launch {
      val result = api.setReaction(appeal.id, IhomeReactionRequest(reaction, !value))
      if (currentEpoch != epoch) return@launch
      val reload = state.value.loading
      if (reload) {
        listVersion++
        listJob?.cancel()
      }
      state.value = state.value.copy(busy = state.value.busy - appeal.id)
      result
          .onSuccess { outcome ->
            outcome.appeal?.let(::replaceAppeal)
            if (!outcome.confirmed)
                state.value =
                    state.value.copy(
                        uncertain = state.value.uncertain + appeal.id,
                        error = outcome.message,
                    )
          }
          .onFailure {
            state.value =
                state.value.copy(
                    uncertain = state.value.uncertain + appeal.id,
                    error = "操作结果未确认，请打开详情刷新后再操作",
                )
          }
      if (reload) refresh()
    }
  }

  private fun replaceAppeal(appeal: IhomeAppeal) {
    val current = state.value
    state.value =
        current.copy(
            entries =
                current.entries
                    .map { if (it.appeal.id == appeal.id) it.copy(appeal = appeal) else it }
                    .filterNot {
                      current.view == IhomeView.FOLLOWED &&
                          it.appeal.id == appeal.id &&
                          appeal.isFollowed == false
                    },
            detail = if (current.detail?.id == appeal.id) appeal else current.detail,
        )
  }
}
