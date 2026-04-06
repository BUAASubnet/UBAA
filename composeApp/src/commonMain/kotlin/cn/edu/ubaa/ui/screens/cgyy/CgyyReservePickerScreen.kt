package cn.edu.ubaa.ui.screens.cgyy

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.ExperimentalMaterialApi
import androidx.compose.material.pullrefresh.PullRefreshIndicator
import androidx.compose.material.pullrefresh.pullRefresh
import androidx.compose.material.pullrefresh.rememberPullRefreshState
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.edu.ubaa.model.dto.CgyyReservationSelectionDto
import cn.edu.ubaa.model.dto.CgyySpaceAvailabilityDto
import cn.edu.ubaa.model.dto.CgyyTimeSlotDto
import cn.edu.ubaa.model.dto.CgyyVenueSiteDto
import kotlin.time.Clock
import kotlinx.datetime.DayOfWeek
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime

private val roomColumnWidth = 112.dp
private val timeSlotColumnWidth = 86.dp
private val tableHeaderHeight = 62.dp
private val tableRowHeight = 56.dp

@OptIn(ExperimentalMaterialApi::class)
@Composable
fun CgyyReservePickerScreen(
    viewModel: CgyyViewModel,
    onNext: () -> Unit,
) {
  val uiState by viewModel.uiState.collectAsState()

  if (uiState.isInitialLoading && uiState.sites.isEmpty()) {
    CgyyLoadingState("正在加载场地与可预约信息...")
    return
  }

  if (uiState.initialError != null && uiState.sites.isEmpty()) {
    CgyyErrorState(uiState.initialError, onRetry = viewModel::loadInitialData)
    return
  }

  val campusOptions =
      listOf(CgyyViewModel.ALL_CAMPUSES) +
          uiState.sites.map { it.campusName }.distinct().sortedBy { campusSortKey(it) }
  val selectedCampus = uiState.selectedCampus.ifBlank { CgyyViewModel.ALL_CAMPUSES }
  val campusSites =
      if (selectedCampus == CgyyViewModel.ALL_CAMPUSES) {
        uiState.sites
      } else {
        uiState.sites.filter { it.campusName == selectedCampus }
      }
  val visibleSites = campusSites
  val availableDates = uiState.dayInfo?.availableDates.orEmpty()
  val visibleSpaces = uiState.dayInfo?.spaces.orEmpty()
  val pullRefreshState =
      rememberPullRefreshState(
          refreshing = uiState.isInitialLoading || uiState.isDayInfoLoading,
          onRefresh = viewModel::refreshReserveData,
      )

  Scaffold(
      bottomBar = {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        ) {
          Button(
              onClick = onNext,
              enabled = viewModel.canAdvanceToReservationForm(),
              modifier =
                  Modifier.fillMaxWidth()
                      .padding(horizontal = 16.dp, vertical = 12.dp)
                      .height(52.dp),
          ) {
            Text("下一步")
          }
        }
      }
  ) { innerPadding ->
    Box(
        modifier =
            Modifier.fillMaxSize()
                .padding(bottom = innerPadding.calculateBottomPadding())
                .pullRefresh(pullRefreshState)
    ) {
      Column(modifier = Modifier.fillMaxSize()) {
        LazyRow(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
          items(campusOptions) { campus ->
            FilterChip(
                selected = selectedCampus == campus,
                onClick = { viewModel.setReserveCampus(campus) },
                label = {
                  Text(
                      text = campusDisplayName(campus),
                      maxLines = 1,
                      overflow = TextOverflow.Ellipsis,
                  )
                },
            )
          }
        }

        if (availableDates.isNotEmpty()) {
          LazyRow(
              modifier = Modifier.fillMaxWidth(),
              contentPadding = PaddingValues(horizontal = 16.dp, vertical = 4.dp),
              horizontalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            items(availableDates) { date ->
              FilterChip(
                  selected = uiState.selectedDate == date,
                  onClick = { viewModel.selectDate(date) },
                  label = {
                    Text(
                        text = formatCompactDateLabel(date),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                  },
              )
            }
          }
        }

        if (visibleSites.isNotEmpty()) {
          LazyRow(
              modifier = Modifier.fillMaxWidth(),
              contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
              horizontalArrangement = Arrangement.spacedBy(8.dp),
          ) {
            items(visibleSites) { site ->
              FilterChip(
                  selected = uiState.selectedSiteId == site.id,
                  onClick = { viewModel.selectSite(site.id) },
                  label = {
                    Text(
                        text = siteSelectionLabel(site),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                  },
              )
            }
          }
        }

        when {
          uiState.isDayInfoLoading ->
              CgyyLoadingState("正在刷新可预约时段...", modifier = Modifier.fillMaxSize())
          uiState.dayInfoError != null ->
              CgyyErrorState(uiState.dayInfoError, onRetry = viewModel::refreshReserveData)
          uiState.selectedSiteId == null -> CgyyEmptyState("请选择楼栋/层", "先从上方横向列表中选择一个研讨室位置。")
          visibleSpaces.isEmpty() -> CgyyEmptyState("暂无可预约教室", "当前楼栋或搜索条件下没有匹配教室。")
          else ->
              CgyyReservationTable(
                  spaces = visibleSpaces,
                  timeSlots = uiState.dayInfo?.timeSlots.orEmpty(),
                  selectedSelections = uiState.selections,
                  onSlotToggle = viewModel::toggleSlot,
              )
        }
      }

      PullRefreshIndicator(
          refreshing = uiState.isInitialLoading || uiState.isDayInfoLoading,
          state = pullRefreshState,
          modifier = Modifier.align(Alignment.TopCenter),
      )
    }
  }
}

@Composable
private fun CgyyReservationTable(
    spaces: List<CgyySpaceAvailabilityDto>,
    timeSlots: List<CgyyTimeSlotDto>,
    selectedSelections: List<CgyyReservationSelectionDto>,
    onSlotToggle: (Int, Int, Int?) -> Unit,
) {
  val horizontalScroll = rememberScrollState()
  LazyColumn(modifier = Modifier.fillMaxSize()) {
    item {
      Row(
          modifier =
              Modifier.fillMaxWidth()
                  .horizontalScroll(horizontalScroll)
                  .background(MaterialTheme.colorScheme.surface)
                  .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
      ) {
        CgyyTableRoomHeaderCell("教室")
        timeSlots.forEach { slot -> CgyyTableTimeHeaderCell(slot) }
      }
    }
    items(spaces) { space ->
      Row(
          modifier =
              Modifier.fillMaxWidth()
                  .height(tableRowHeight)
                  .horizontalScroll(horizontalScroll)
                  .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
      ) {
        Box(
            modifier =
                Modifier.width(roomColumnWidth)
                    .fillMaxHeight()
                    .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
                    .padding(horizontal = 8.dp),
            contentAlignment = Alignment.CenterStart,
        ) {
          Text(
              text = space.spaceName,
              style = MaterialTheme.typography.bodyMedium,
              fontWeight = FontWeight.Bold,
              fontSize = 15.sp,
              maxLines = 1,
              overflow = TextOverflow.Ellipsis,
          )
        }

        timeSlots.forEach { slot ->
          val slotState = space.slots.firstOrNull { it.timeId == slot.id }
          val selected =
              selectedSelections.any { it.spaceId == space.spaceId && it.timeId == slot.id }
          val isReservable = slotState?.isReservable == true
          val background =
              when {
                selected -> MaterialTheme.colorScheme.primary
                isReservable -> Color(0xFF98FB98)
                else -> Color.Transparent
              }

          Box(
              modifier =
                  Modifier.width(timeSlotColumnWidth)
                      .fillMaxHeight()
                      .background(background)
                      .border(0.3.dp, MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
                      .padding(2.dp),
              contentAlignment = Alignment.Center,
          ) {
            TextButton(
                onClick = {
                  if (slotState != null && (isReservable || selected)) {
                    onSlotToggle(space.spaceId, slot.id, space.venueSpaceGroupId)
                  }
                },
                enabled = slotState != null && (isReservable || selected),
                contentPadding = PaddingValues(0.dp),
                modifier = Modifier.fillMaxSize(),
            ) {
              Text(
                  text = if (selected) "已选" else "",
                  color =
                      if (selected) {
                        MaterialTheme.colorScheme.onPrimary
                      } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                      },
                  fontSize = 11.sp,
              )
            }
          }
        }
      }
    }
    item { Spacer(modifier = Modifier.height(16.dp)) }
  }
}

@Composable
private fun CgyyTableRoomHeaderCell(text: String) {
  Box(
      modifier =
          Modifier.width(roomColumnWidth)
              .height(tableHeaderHeight)
              .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
              .padding(horizontal = 8.dp),
      contentAlignment = Alignment.CenterStart,
  ) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
  }
}

@Composable
private fun CgyyTableTimeHeaderCell(slot: CgyyTimeSlotDto) {
  Column(
      modifier =
          Modifier.width(timeSlotColumnWidth)
              .height(tableHeaderHeight)
              .border(0.5.dp, MaterialTheme.colorScheme.outlineVariant)
              .padding(horizontal = 4.dp, vertical = 6.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.Center,
  ) {
    Text(
        text = slot.beginTime,
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Bold,
        textAlign = TextAlign.Center,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
    Text(
        text = "-${slot.endTime}",
        style = MaterialTheme.typography.labelSmall,
        textAlign = TextAlign.Center,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
    )
  }
}

private fun siteSelectionLabel(site: CgyyVenueSiteDto): String = buildString {
  append(shortVenueName(site.venueName))
  if (site.siteName.isNotBlank()) {
    append(" / ")
    append(site.siteName)
  }
}

private fun shortVenueName(name: String): String = name.removeSuffix("研讨室").ifBlank { name }

private fun campusDisplayName(name: String): String =
    when {
      name.contains("学院路") -> "学院路"
      name.contains("沙河") -> "沙河"
      else -> name
    }

private fun campusSortKey(name: String): Int =
    when {
      name.contains("学院路") -> 0
      name.contains("沙河") -> 1
      else -> 99
    }

private fun formatCompactDateLabel(date: String): String =
    if (date.length >= 10) "${date.takeLast(5)} ${dateWeekdaySuffix(date)}" else date

private fun dateWeekdaySuffix(date: String): String {
  val parsedDate = runCatching { LocalDate.parse(date) }.getOrNull() ?: return ""
  val weekday =
      when (parsedDate.dayOfWeek) {
        DayOfWeek.MONDAY -> "周一"
        DayOfWeek.TUESDAY -> "周二"
        DayOfWeek.WEDNESDAY -> "周三"
        DayOfWeek.THURSDAY -> "周四"
        DayOfWeek.FRIDAY -> "周五"
        DayOfWeek.SATURDAY -> "周六"
        DayOfWeek.SUNDAY -> "周日"
      }
  val today = Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date.toString()
  return if (date == today) "今天" else weekday
}
