package cn.edu.ubaa.ui.screens.classroom

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.edu.ubaa.api.ClassroomApi
import cn.edu.ubaa.model.dto.ClassroomInfo
import cn.edu.ubaa.model.dto.ClassroomQueryResponse
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

internal const val ALL_BUILDINGS = "\u5168\u90e8"
private const val UNKNOWN_ERROR = "\u672a\u77e5\u9519\u8bef"

sealed class ClassroomUiState {
  object Idle : ClassroomUiState()

  object Loading : ClassroomUiState()

  data class Success(val data: ClassroomQueryResponse) : ClassroomUiState()

  data class Error(val message: String) : ClassroomUiState()
}

class ClassroomViewModel(private val api: ClassroomApi = ClassroomApi()) : ViewModel() {
  private val _uiState = MutableStateFlow<ClassroomUiState>(ClassroomUiState.Idle)
  val uiState: StateFlow<ClassroomUiState> = _uiState.asStateFlow()

  private val _xqid = MutableStateFlow(1)
  val xqid: StateFlow<Int> = _xqid.asStateFlow()

  private val _date = MutableStateFlow(getCurrentDate())
  val date: StateFlow<String> = _date.asStateFlow()

  private val _searchQuery = MutableStateFlow("")
  val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

  private val _selectedBuilding = MutableStateFlow(ALL_BUILDINGS)
  val selectedBuilding: StateFlow<String> = _selectedBuilding.asStateFlow()

  val availableBuildings: StateFlow<List<String>> =
    _uiState
      .map { state ->
        if (state is ClassroomUiState.Success) {
          buildingOptionsFrom(state.data.d.list)
        } else {
          listOf(ALL_BUILDINGS)
        }
      }
      .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), listOf(ALL_BUILDINGS))

  val filteredData: StateFlow<Map<String, List<ClassroomInfo>>> =
    combine(_uiState, _searchQuery, _selectedBuilding) { state, query, building ->
        if (state is ClassroomUiState.Success) {
          filterClassroomData(state.data.d.list, query, building)
        } else {
          emptyMap()
        }
      }
      .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyMap())

  fun setSearchQuery(query: String) {
    _searchQuery.value = query
  }

  fun setSelectedBuilding(building: String) {
    _selectedBuilding.value = building
  }

  fun setXqid(id: Int) {
    _xqid.value = id
    _selectedBuilding.value = ALL_BUILDINGS
    query()
  }

  fun setDate(date: String) {
    _date.value = date
    query()
  }

  fun query() {
    viewModelScope.launch {
      _uiState.value = ClassroomUiState.Loading
      api
        .queryClassrooms(_xqid.value, _date.value)
        .onSuccess { response ->
          if (_selectedBuilding.value != ALL_BUILDINGS &&
            _selectedBuilding.value !in response.d.list.keys) {
            _selectedBuilding.value = ALL_BUILDINGS
          }
          _uiState.value = ClassroomUiState.Success(response)
        }
        .onFailure { _uiState.value = ClassroomUiState.Error(it.message ?: UNKNOWN_ERROR) }
    }
  }

  @OptIn(ExperimentalTime::class)
  private fun getCurrentDate(): String {
    val now = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault())
    return "${now.year}-${now.monthNumber.toString().padStart(2, '0')}-${now.dayOfMonth.toString().padStart(2, '0')}"
  }
}

internal fun filterClassroomData(
  allData: Map<String, List<ClassroomInfo>>,
  query: String,
  selectedBuilding: String,
): Map<String, List<ClassroomInfo>> {
  val buildingFiltered =
    if (selectedBuilding == ALL_BUILDINGS) {
      allData
    } else {
      allData.filterKeys { it == selectedBuilding }
    }

  if (query.isBlank()) return buildingFiltered

  return buildingFiltered
    .mapValues { (_, list) -> list.filter { it.name.contains(query, ignoreCase = true) } }
    .filterValues { it.isNotEmpty() }
}

internal fun buildingOptionsFrom(allData: Map<String, List<ClassroomInfo>>): List<String> {
  return listOf(ALL_BUILDINGS) + sortBuildings(allData)
}

internal fun sortBuildings(allData: Map<String, List<ClassroomInfo>>): List<String> {
  val analysis = analyzeBuildingFloorIds(allData)
  return if (analysis.canUseFloorIdOrdering) {
    analysis.entries
      .sortedWith(
        compareBy<BuildingFloorAnalysisEntry> { it.floorId }
          .thenComparator { left, right -> naturalCompare(left.name, right.name) }
      )
      .map { it.name }
  } else {
    allData.keys.sortedWith(::naturalCompare)
  }
}

internal fun analyzeBuildingFloorIds(
  allData: Map<String, List<ClassroomInfo>>
): BuildingFloorAnalysis {
  val entries =
    allData.map { (building, classrooms) ->
      val floorIds = classrooms.map { it.floorid.trim() }.filter { it.isNotEmpty() }.toSet()
      BuildingFloorAnalysisEntry(
        name = building,
        floorIds = floorIds,
        floorId = floorIds.singleOrNull(),
      )
    }

  val canUseFloorIdOrdering =
    entries.isNotEmpty() &&
      entries.all { it.floorIds.size == 1 && it.floorId != null } &&
      entries.mapNotNull { it.floorId }.distinct().size == entries.size

  return BuildingFloorAnalysis(entries = entries, canUseFloorIdOrdering = canUseFloorIdOrdering)
}

internal data class BuildingFloorAnalysis(
  val entries: List<BuildingFloorAnalysisEntry>,
  val canUseFloorIdOrdering: Boolean,
)

internal data class BuildingFloorAnalysisEntry(
  val name: String,
  val floorIds: Set<String>,
  val floorId: String?,
)

internal fun naturalCompare(left: String, right: String): Int {
  val leftParts = splitNaturalParts(left)
  val rightParts = splitNaturalParts(right)
  val maxSize = maxOf(leftParts.size, rightParts.size)
  for (index in 0 until maxSize) {
    val leftPart = leftParts.getOrNull(index) ?: return -1
    val rightPart = rightParts.getOrNull(index) ?: return 1
    val result =
      when {
        leftPart is NaturalPart.Number && rightPart is NaturalPart.Number ->
          leftPart.value.compareTo(rightPart.value)
        leftPart is NaturalPart.Text && rightPart is NaturalPart.Text ->
          leftPart.value.compareTo(rightPart.value)
        leftPart is NaturalPart.Number -> -1
        else -> 1
      }
    if (result != 0) return result
  }
  return 0
}

internal fun splitNaturalParts(value: String): List<NaturalPart> {
  if (value.isEmpty()) return emptyList()

  val parts = mutableListOf<NaturalPart>()
  val buffer = StringBuilder()
  var digitMode = value.first().isDigit()

  fun flush() {
    if (buffer.isEmpty()) return
    val text = buffer.toString()
    parts +=
      if (digitMode) {
        NaturalPart.Number(text.toIntOrNull() ?: Int.MAX_VALUE)
      } else {
        NaturalPart.Text(text)
      }
    buffer.clear()
  }

  value.forEach { char ->
    val isDigit = char.isDigit()
    if (buffer.isNotEmpty() && isDigit != digitMode) {
      flush()
      digitMode = isDigit
    } else if (buffer.isEmpty()) {
      digitMode = isDigit
    }
    buffer.append(char)
  }
  flush()

  return parts
}

internal sealed interface NaturalPart {
  data class Number(val value: Int) : NaturalPart

  data class Text(val value: String) : NaturalPart
}
