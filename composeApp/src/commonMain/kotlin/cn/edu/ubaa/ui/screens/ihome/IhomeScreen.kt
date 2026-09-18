package cn.edu.ubaa.ui.screens.ihome

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Article
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import cn.edu.ubaa.model.dto.*

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IhomeScreen(viewModel: IhomeViewModel) {
  val state by viewModel.uiState.collectAsState()
  var draft by remember(state.query.keyword) { mutableStateOf(state.query.keyword) }
  val listState = rememberLazyListState()
  LaunchedEffect(Unit) { viewModel.ensureLoaded() }
  LaunchedEffect(state.view, state.query.keyword, state.query.filter, state.query.categoryId) {
    listState.scrollToItem(0)
  }

  Surface(Modifier.fillMaxSize()) {
    Column(Modifier.fillMaxSize()) {
      Row(
          Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
          verticalAlignment = Alignment.CenterVertically,
      ) {
        OutlinedTextField(
            value = draft,
            onValueChange = { draft = it.take(200) },
            modifier = Modifier.weight(1f),
            label = { Text("搜索诉求与回复") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { viewModel.search(draft) }),
            trailingIcon = {
              IconButton(onClick = { viewModel.search(draft) }) { Icon(Icons.Default.Search, "搜索") }
            },
        )
        IconButton(
            onClick = {
              viewModel.refresh()
              if (state.configError != null) viewModel.loadConfig()
            },
            enabled = !state.loading,
        ) {
          Icon(Icons.Default.Refresh, "刷新")
        }
      }
      SecondaryScrollableTabRow(selectedTabIndex = state.view.ordinal, edgePadding = 8.dp) {
        IhomeView.entries.forEach { view ->
          Tab(
              selected = view == state.view,
              onClick = { viewModel.selectView(view) },
              text = { Text(view.title, maxLines = 1) },
          )
        }
      }
      if (state.view in listOf(IhomeView.PUBLIC, IhomeView.MINE)) IhomeFilters(state, viewModel)
      state.configError?.let { ErrorRow(it, viewModel::loadConfig) }
      state.error?.let { ErrorRow(it, viewModel::refresh) }
      if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
      LazyColumn(
          state = listState,
          modifier = Modifier.weight(1f),
          contentPadding = PaddingValues(bottom = 24.dp),
      ) {
        if (state.view == IhomeView.NOTICES) {
          items(state.notices, key = { it.id }) { notice ->
            ListItem(
                headlineContent = {
                  Text(notice.title, maxLines = 3, overflow = TextOverflow.Ellipsis)
                },
                leadingContent = { Icon(Icons.AutoMirrored.Filled.Article, null) },
                modifier = Modifier.clickable { viewModel.openNotice(notice.id) },
            )
            HorizontalDivider()
          }
        } else {
          items(
              state.entries,
              key = { it.evaluation?.let { e -> "评价:${e.id}" } ?: "诉求:${it.appeal.id}" },
          ) { entry ->
            AppealRow(
                entry,
                state,
                onOpen = { viewModel.openDetail(entry.appeal.id) },
                onReact = viewModel::react,
            )
            HorizontalDivider()
          }
        }
        if (
            !state.loading &&
                state.error == null &&
                state.entries.isEmpty() &&
                (state.view != IhomeView.NOTICES || state.notices.isEmpty())
        ) {
          item {
            Box(Modifier.fillMaxWidth().padding(40.dp), contentAlignment = Alignment.Center) {
              Text(if (state.view == IhomeView.FOLLOWED) "暂无关注的诉求" else "暂无内容")
            }
          }
        }
        if (state.hasMore)
            item {
              Box(Modifier.fillMaxWidth().padding(16.dp), contentAlignment = Alignment.Center) {
                TextButton(onClick = viewModel::loadMore, enabled = !state.loading) { Text("加载更多") }
              }
            }
      }
    }
  }
  if (state.selectedId != null) IhomeDetailDialog(state, viewModel)
}

@Composable
private fun IhomeFilters(state: IhomeUiState, viewModel: IhomeViewModel) {
  var expanded by remember { mutableStateOf(false) }
  val options =
      if (state.view == IhomeView.PUBLIC)
          listOf(
              IhomeFilter.ALL,
              IhomeFilter.NEWEST,
              IhomeFilter.OLDEST,
              IhomeFilter.REPLIED,
              IhomeFilter.UNREPLIED,
          )
      else
          listOf(
              IhomeFilter.NEWEST,
              IhomeFilter.REPLY_TIME,
              IhomeFilter.REPLIED,
              IhomeFilter.UNREPLIED,
          )
  Box(Modifier.padding(horizontal = 12.dp)) {
    TextButton(onClick = { expanded = true }) {
      Icon(Icons.Default.FilterList, null)
      Spacer(Modifier.width(8.dp))
      Text(
          state.config.categories.firstOrNull { it.id == state.query.categoryId }?.name
              ?: filterLabel(state.query.filter)
      )
      Icon(Icons.Default.ArrowDropDown, null)
    }
    DropdownMenu(expanded, onDismissRequest = { expanded = false }) {
      options.forEach { option ->
        DropdownMenuItem(
            text = { Text(filterLabel(option)) },
            onClick = {
              expanded = false
              viewModel.filter(option)
            },
        )
      }
      if (state.view == IhomeView.PUBLIC && state.config.categories.isNotEmpty()) {
        HorizontalDivider()
        state.config.categories.forEach { category ->
          DropdownMenuItem(
              text = { Text(category.name) },
              onClick = {
                expanded = false
                viewModel.filter(IhomeFilter.ALL, category.id)
              },
          )
        }
      }
    }
  }
}

private fun filterLabel(filter: IhomeFilter) =
    when (filter) {
      IhomeFilter.ALL -> "全部诉求"
      IhomeFilter.NEWEST -> "最新发布"
      IhomeFilter.OLDEST -> "最早发布"
      IhomeFilter.REPLIED -> "已回复"
      IhomeFilter.UNREPLIED -> "未回复"
      IhomeFilter.REPLY_TIME -> "按回复时间"
    }

@Composable
private fun AppealRow(
    entry: IhomeEntry,
    state: IhomeUiState,
    onOpen: () -> Unit,
    onReact: (IhomeAppeal, IhomeReaction) -> Unit,
) {
  val appeal = entry.appeal
  Column(
      Modifier.fillMaxWidth()
          .clickable(onClick = onOpen)
          .padding(horizontal = 16.dp, vertical = 12.dp),
      verticalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    Text(
        listOf(appeal.category, appeal.status).filter { it.isNotBlank() }.joinToString(" · "),
        style = MaterialTheme.typography.labelMedium,
        color = MaterialTheme.colorScheme.primary,
    )
    Text(
        appeal.content,
        maxLines = 4,
        overflow = TextOverflow.Ellipsis,
        style = MaterialTheme.typography.bodyLarge,
    )
    if (appeal.departments.isNotEmpty())
        Text(
            appeal.departments.joinToString("、"),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    appeal.replies.firstOrNull()?.let { reply ->
      Text(
          "${reply.department}：${reply.content}",
          maxLines = 2,
          overflow = TextOverflow.Ellipsis,
          style = MaterialTheme.typography.bodyMedium,
          color = MaterialTheme.colorScheme.onSurfaceVariant,
      )
    }
    entry.evaluation?.let { Evaluation(it) }
    if (appeal.publishedAt.isNotBlank())
        Text(appeal.publishedAt, style = MaterialTheme.typography.labelSmall)
    ReactionRow(appeal, state, onReact)
  }
}

@Composable
private fun ReactionRow(
    appeal: IhomeAppeal,
    state: IhomeUiState,
    onReact: (IhomeAppeal, IhomeReaction) -> Unit,
) {
  val enabled = appeal.id !in state.busy && appeal.id !in state.uncertain
  Row(
      verticalAlignment = Alignment.CenterVertically,
      horizontalArrangement = Arrangement.spacedBy(8.dp),
  ) {
    appeal.isFollowed?.let { selected ->
      IconToggleButton(
          checked = selected,
          onCheckedChange = { onReact(appeal, IhomeReaction.FOLLOW) },
          enabled = enabled,
      ) {
        Icon(
            if (selected) Icons.Default.Star else Icons.Default.StarBorder,
            if (selected) "取消关注" else "关注",
        )
      }
      Text(appeal.followCount?.toString().orEmpty(), style = MaterialTheme.typography.labelMedium)
    }
    if (state.config.supportEnabled)
        appeal.isSupported?.let { selected ->
          IconToggleButton(
              checked = selected,
              onCheckedChange = { onReact(appeal, IhomeReaction.SUPPORT) },
              enabled = enabled,
          ) {
            Icon(
                if (selected) Icons.Default.ThumbUp else Icons.Outlined.ThumbUp,
                if (selected) "取消${state.config.supportLabel}" else state.config.supportLabel,
            )
          }
          Text(
              appeal.supportCount?.toString().orEmpty(),
              style = MaterialTheme.typography.labelMedium,
          )
        }
    if (appeal.id in state.busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
  }
}

@Composable
private fun IhomeDetailDialog(state: IhomeUiState, viewModel: IhomeViewModel) {
  Dialog(
      onDismissRequest = viewModel::closeDetail,
      properties = DialogProperties(usePlatformDefaultWidth = false),
  ) {
    Surface(
        Modifier.widthIn(max = 840.dp).fillMaxWidth(0.94f).fillMaxHeight(0.9f),
        shape = MaterialTheme.shapes.medium,
    ) {
      Column {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
          Text(
              if (state.view == IhomeView.NOTICES) "公告详情" else "诉求详情",
              modifier = Modifier.weight(1f),
              style = MaterialTheme.typography.titleMedium,
          )
          IconButton(
              onClick = viewModel::retryDetail,
              enabled = !state.detailLoading && state.busy.isEmpty(),
          ) {
            Icon(Icons.Default.Refresh, "刷新详情")
          }
          IconButton(onClick = viewModel::closeDetail) { Icon(Icons.Default.Close, "关闭详情") }
        }
        HorizontalDivider()
        if (state.detailLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
        state.detailError?.let { ErrorRow(it, viewModel::retryDetail) }
        state.error?.let { ErrorRow(it, viewModel::retryDetail) }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
          state.notice?.let { notice ->
            Text(notice.title, style = MaterialTheme.typography.titleLarge)
            Text(notice.date, style = MaterialTheme.typography.labelMedium)
            SelectionContainer { Text(notice.content) }
          }
          state.detail?.let { appeal ->
            Text(
                listOf(appeal.category, appeal.status, appeal.publishedAt)
                    .filter { it.isNotBlank() }
                    .joinToString(" · "),
                style = MaterialTheme.typography.labelMedium,
            )
            SelectionContainer { Text(appeal.content, style = MaterialTheme.typography.bodyLarge) }
            ReactionRow(appeal, state, viewModel::react)
            if (appeal.history.isNotEmpty()) {
              HorizontalDivider()
              Text("处理进度", style = MaterialTheme.typography.titleMedium)
              appeal.history.forEach {
                Text("${it.createdAt}\n${it.content}", style = MaterialTheme.typography.bodyMedium)
              }
            }
            HorizontalDivider()
            Text("回复", style = MaterialTheme.typography.titleMedium)
            if (appeal.replies.isEmpty())
                Text("暂无回复", color = MaterialTheme.colorScheme.onSurfaceVariant)
            appeal.replies.forEach { reply ->
              Text(reply.department, fontWeight = FontWeight.SemiBold)
              SelectionContainer { Text(reply.content) }
              Text(reply.createdAt, style = MaterialTheme.typography.labelSmall)
            }
            if (appeal.evaluations.isNotEmpty()) {
              HorizontalDivider()
              Text("评价", style = MaterialTheme.typography.titleMedium)
              appeal.evaluations.forEach { Evaluation(it) }
            }
          }
        }
      }
    }
  }
}

@Composable
private fun Evaluation(evaluation: IhomeEvaluation) {
  Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
    Text(evaluation.department, style = MaterialTheme.typography.labelLarge)
    Text(evaluation.content, style = MaterialTheme.typography.bodyMedium)
    Text(
        "响应时间 ${evaluation.speed}/5\n回复满意度 ${evaluation.satisfaction}/5\n问题解决程度 ${evaluation.degree}/5",
        style = MaterialTheme.typography.labelMedium,
    )
  }
}

@Composable
private fun ErrorRow(message: String, retry: () -> Unit) {
  Row(
      Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
      verticalAlignment = Alignment.CenterVertically,
  ) {
    Text(
        message,
        Modifier.weight(1f),
        color = MaterialTheme.colorScheme.error,
        style = MaterialTheme.typography.bodyMedium,
    )
    IconButton(onClick = retry) { Icon(Icons.Default.Refresh, "重试") }
  }
}
