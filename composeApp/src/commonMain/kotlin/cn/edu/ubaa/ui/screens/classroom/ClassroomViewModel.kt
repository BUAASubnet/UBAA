package cn.edu.ubaa.ui.screens.classroom

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.ClassroomApi
import cn.edu.ubaa.model.dto.ClassroomInfo
import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

sealed class ClassroomUiState {
    object Idle : ClassroomUiState()
    object Loading : ClassroomUiState()
    data class Success(val data: ClassroomQueryResponse) : ClassroomUiState()
    data class Error(val message: String) : ClassroomUiState()
}

class ClassroomViewModel(private val api: ClassroomApi = ClassroomApi()) : ViewModel() {
    private val _uiState = MutableStateFlow<ClassroomUiState>(ClassroomUiState.Idle)
    val uiState: StateFlow<ClassroomUiState> = _uiState.asStateFlow()

    private val _xqid = MutableStateFlow(1) // 1: 学院路, 2: 沙河, 3: 杭研院
    val xqid: StateFlow<Int> = _xqid.asStateFlow()

    private val _date = MutableStateFlow(getCurrentDate())
    val date: StateFlow<String> = _date.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    val filteredData: StateFlow<Map<String, List<ClassroomInfo>>> =
            combine(_uiState, _searchQuery) { state, query ->
                        if (state is ClassroomUiState.Success) {
                            val allData = state.data.d.list
                            if (query.isBlank()) {
                                allData
                            } else {
                                allData
                                        .mapValues { (_, classrooms) ->
                                            classrooms.filter {
                                                it.name.contains(query, ignoreCase = true)
                                            }
                                        }
                                        .filter { (building, classrooms) ->
                                            building.contains(query, ignoreCase = true) ||
                                                    classrooms.isNotEmpty()
                                        }
                            }
                        } else {
                            emptyMap()
                        }
                    }
                    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())

    fun setSearchQuery(query: String) {
        _searchQuery.value = query
    }

    fun setXqid(id: Int) {
        _xqid.value = id
        query()
    }

    fun setDate(date: String) {
        _date.value = date
        query()
    }

    fun query() {
        viewModelScope.launch {
            _uiState.value = ClassroomUiState.Loading
            api.queryClassrooms(_xqid.value, _date.value)
                    .onSuccess { _uiState.value = ClassroomUiState.Success(it) }
                    .onFailure {
                        _uiState.value = ClassroomUiState.Error(it.message ?: "Unknown error")
                    }
        }
    }

    private fun getCurrentDate(): String {
        val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
        return "${now.year}-${now.monthNumber.toString().padStart(2, '0')}-${now.dayOfMonth.toString().padStart(2, '0')}"
    }
}
