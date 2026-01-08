package cn.edu.ubaa.ui.screens.classroom

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.ClassroomApi
import cn.edu.ubaa.model.dto.ClassroomInfo
import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

/** 教室查询 UI 状态密封类。 */
sealed class ClassroomUiState {
  object Idle : ClassroomUiState()

  object Loading : ClassroomUiState()

  data class Success(val data: ClassroomQueryResponse) : ClassroomUiState()

  data class Error(val message: String) : ClassroomUiState()
}

/** 教室查询模块的 ViewModel。 负责校区选择、日期选择以及在结果中进行模糊搜索过滤。 */
class ClassroomViewModel(private val api: ClassroomApi = ClassroomApi()) : ViewModel() {
  private val _uiState = MutableStateFlow<ClassroomUiState>(ClassroomUiState.Idle)
  /** 核心查询状态流。 */
  val uiState: StateFlow<ClassroomUiState> = _uiState.asStateFlow()

  private val _xqid = MutableStateFlow(1) // 1: 学院路, 2: 沙河, 3: 杭州
  /** 当前选中的校区 ID。 */
  val xqid: StateFlow<Int> = _xqid.asStateFlow()

  private val _date = MutableStateFlow(getCurrentDate())
  /** 当前选中的查询日期。 */
  val date: StateFlow<String> = _date.asStateFlow()

  private val _searchQuery = MutableStateFlow("")
  /** 当前的搜索关键字流。 */
  val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

  /** 根据搜索关键字过滤后的教室数据流。 自动响应 uiState 和 searchQuery 的变化。 */
  val filteredData: StateFlow<Map<String, List<ClassroomInfo>>> =
          combine(_uiState, _searchQuery) { state, query ->
                    if (state is ClassroomUiState.Success) {
                      val allData = state.data.d.list
                      if (query.isBlank()) allData
                      else
                              allData
                                      .mapValues { (_, list) ->
                                        list.filter { it.name.contains(query, true) }
                                      }
                                      .filter { (building, list) ->
                                        building.contains(query, true) || list.isNotEmpty()
                                      }
                    } else emptyMap()
                  }
                  .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())

  /** 更新搜索关键字。 */
  fun setSearchQuery(query: String) {
    _searchQuery.value = query
  }

  /** 切换校区并自动重新查询。 */
  fun setXqid(id: Int) {
    _xqid.value = id
    query()
  }

  /** 切换日期并自动重新查询。 */
  fun setDate(date: String) {
    _date.value = date
    query()
  }

  /** 执行查询动作。 */
  fun query() {
    viewModelScope.launch {
      _uiState.value = ClassroomUiState.Loading
      api.queryClassrooms(_xqid.value, _date.value)
              .onSuccess { _uiState.value = ClassroomUiState.Success(it) }
              .onFailure { _uiState.value = ClassroomUiState.Error(it.message ?: "未知错误") }
    }
  }

  @OptIn(ExperimentalTime::class)
  private fun getCurrentDate(): String {
    val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    return "${now.year}-${now.monthNumber.toString().padStart(2, '0')}-${now.dayOfMonth.toString().padStart(2, '0')}"
  }
}
