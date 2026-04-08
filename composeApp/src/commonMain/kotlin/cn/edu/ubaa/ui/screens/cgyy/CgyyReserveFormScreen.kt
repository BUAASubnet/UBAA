package cn.edu.ubaa.ui.screens.cgyy

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

@Composable
fun CgyyReserveFormScreen(
    viewModel: CgyyViewModel,
    onBackToSelection: () -> Unit,
    onSubmitSuccess: () -> Unit,
) {
  val uiState by viewModel.uiState.collectAsState()
  var showPurposeDialog by remember { mutableStateOf(false) }

  val summary = uiState.reservationSummary
  if (summary == null) {
    CgyyEmptyState("还没有选择预约时段", "请先返回上一页选择研讨室、日期和时段。")
    return
  }

  if (showPurposeDialog) {
    CgyyPurposeTypeDialog(
        options = uiState.purposeTypes,
        selected = uiState.purposeType,
        onDismiss = { showPurposeDialog = false },
        onSelect = {
          viewModel.updatePurposeType(it)
          showPurposeDialog = false
        },
    )
  }

  val hasTriedSubmit = uiState.hasTriedSubmitReservation
  val joinerNum = uiState.joinerNum.toIntOrNull()
  val phoneError = hasTriedSubmit && uiState.phone.isBlank()
  val themeError = hasTriedSubmit && uiState.theme.isBlank()
  val joinerNumError = hasTriedSubmit && (joinerNum == null || joinerNum <= 0)
  val activityContentError = hasTriedSubmit && uiState.activityContent.isBlank()
  val joinersError = hasTriedSubmit && uiState.joiners.isBlank()

  Scaffold(
      contentWindowInsets =
          WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom),
      bottomBar = {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          Button(
              onClick = onBackToSelection,
              modifier = Modifier.weight(1f).height(52.dp),
              contentPadding = PaddingValues(horizontal = 16.dp),
          ) {
            Text("返回修改时段")
          }
          Button(
              onClick = { viewModel.submitReservation(onSuccess = onSubmitSuccess) },
              enabled = !uiState.isSubmitting,
              modifier = Modifier.weight(1.4f).height(52.dp),
              contentPadding = PaddingValues(horizontal = 16.dp),
          ) {
            Text(if (uiState.isSubmitting) "提交中..." else "提交预约")
          }
        }
      },
  ) { innerPadding ->
    Column(
        modifier =
            Modifier.fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(16.dp)
                .padding(bottom = innerPadding.calculateBottomPadding()),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
      uiState.actionMessage?.let { CgyyMessageBanner(it) }

      CgyySectionCard(title = "已选时段") {
        Text(summary.siteLabel, fontWeight = FontWeight.Bold)
        Text(
            "${summary.reservationDate} / ${summary.spaceName}",
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            summary.slotLabels.joinToString("、"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.primary,
        )
      }

      CgyySectionCard(title = "填写预约信息") {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
          OutlinedTextField(
              value = uiState.phone,
              onValueChange = viewModel::updatePhone,
              label = { Text("联系电话 *") },
              modifier = Modifier.fillMaxWidth(),
              singleLine = true,
              isError = phoneError,
              supportingText = { if (phoneError) Text("请填写联系电话") },
          )
          OutlinedTextField(
              value = uiState.theme,
              onValueChange = viewModel::updateTheme,
              label = { Text("活动主题 *") },
              modifier = Modifier.fillMaxWidth(),
              singleLine = true,
              isError = themeError,
              supportingText = { if (themeError) Text("请填写活动主题") },
          )
          OutlinedButton(
              onClick = { showPurposeDialog = true },
              modifier = Modifier.fillMaxWidth(),
          ) {
            Text(
                uiState.purposeTypes.firstOrNull { it.key == uiState.purposeType }?.name ?: "选择活动类型"
            )
          }
          OutlinedTextField(
              value = uiState.joinerNum,
              onValueChange = viewModel::updateJoinerNum,
              label = { Text("参与人数 *") },
              modifier = Modifier.fillMaxWidth(),
              singleLine = true,
              isError = joinerNumError,
              supportingText = { if (joinerNumError) Text("参与人数必须大于 0") },
          )
          OutlinedTextField(
              value = uiState.activityContent,
              onValueChange = viewModel::updateActivityContent,
              label = { Text("活动内容 *") },
              modifier = Modifier.fillMaxWidth(),
              minLines = 3,
              isError = activityContentError,
              supportingText = { if (activityContentError) Text("请填写活动内容") },
          )
          OutlinedTextField(
              value = uiState.joiners,
              onValueChange = viewModel::updateJoiners,
              label = { Text("参与人说明 *") },
              modifier = Modifier.fillMaxWidth(),
              minLines = 2,
              isError = joinersError,
              supportingText = { if (joinersError) Text("请填写参与人说明") },
          )
        }
      }

      CgyySectionCard(title = "附加选项") {
        CgyyToggleRow(
            label = "哲学社会科学相关活动",
            checked = uiState.isPhilosophySocialSciences,
            onCheckedChange = viewModel::setPhilosophySocialSciences,
        )
        Spacer(modifier = Modifier.height(4.dp))
        CgyyToggleRow(
            label = "包含校外参与人员",
            checked = uiState.isOffSchoolJoiner,
            onCheckedChange = viewModel::setOffSchoolJoiner,
        )
      }
    }
  }
}
