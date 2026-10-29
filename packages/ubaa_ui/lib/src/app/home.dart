import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../common/section.dart';
import '../features/home/schedule.dart';
import '../features/home/todo_grid.dart';
import '../shared/loading.dart' show LoadingGlyph, LoadingPlaceholder;
import '../features/grades/notice.dart' show GradeScoreBanner;
import '../shared/feature_icons.dart' show uiFeatureIcon;

class HomeView extends StatefulWidget {
  const HomeView({
    required this.user,
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.onRefresh,
    required this.visible,
    required this.cacheEpoch,
    this.businessCacheEpoch = 0,
    required this.onTodoTap,
    this.onLoadSupplement,
    this.onLoadDaySchedule,
    this.onSignin,
    this.reminderSettings,
    this.onObserveProgress,
    this.gradeScoreNotice,
    this.gradeCheckRoute,
    this.onCheckGradeUpdates,
    this.onOpenGradeNotice,
    this.onDismissGradeNotice,
    this.writeReadbackNotice,
    this.homeClock,
    this.recentFeatures = const [],
  });
  final Clock? homeClock;
  final List<FeatureId> recentFeatures;
  final Widget? writeReadbackNotice;
  final GradeScoreNotice? gradeScoreNotice;
  final ConnectionMode? gradeCheckRoute;
  final Future<void> Function()? onCheckGradeUpdates;
  final VoidCallback? onOpenGradeNotice, onDismissGradeNotice;
  final UserSummary? user;
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final Future<void> Function() onRefresh;
  final bool visible;
  final int cacheEpoch;
  final int businessCacheEpoch;
  final ValueChanged<HomeTodo> onTodoTap;
  final Future<WriteOutcome?> Function(SigninPerformAction)? onSignin;
  final Future<FeatureResult> Function(HomeSupplement, bool)? onLoadSupplement;
  final Future<FeatureResult> Function(String, bool)? onLoadDaySchedule;
  final YgdkReminderSettings? reminderSettings;
  final void Function(WeekPresentation, YgdkOverview)? onObserveProgress;
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  bool _showAllTodos = false;
  String? _signingTodo;
  final _completedSignins = <String>{};
  final _uncertainSignins = <String>{};
  String _signinKey(HomeTodo item) =>
      '${homeCampusTime(_now).toIso8601String().split('T').first}:${item.id}';

  Future<void> _signin(HomeTodo item) async {
    if (_signingTodo != null) return;
    final action = item.signinAction;
    if (action == null || widget.onSignin == null) return;
    final key = _signinKey(item);
    setState(() => _signingTodo = item.id);
    try {
      final outcome = await widget.onSignin!(action);
      if (!mounted) return;
      setState(() {
        if (outcome?.operation == WriteOperation.signinPerform &&
            outcome?.result?.success == true &&
            outcome?.result?.outcomeUnknown == false) {
          _completedSignins.add(key);
        } else if (outcome?.result?.outcomeUnknown == true ||
            outcome?.error?.code == UbaaErrorCode.outcomeUnknown) {
          _uncertainSignins.add(key);
        }
      });
    } finally {
      if (mounted) setState(() => _signingTodo = null);
    }
  }

  Future<void> _refreshSignin(HomeTodo item) async {
    if (_signingTodo != null) return;
    setState(() => _signingTodo = item.id);
    try {
      await widget.onRetryFeature(FeatureId.signin);
      if (mounted &&
          widget.snapshots[FeatureId.signin]?.status ==
              FeatureLoadStatus.success) {
        setState(() => _uncertainSignins.remove(_signinKey(item)));
      }
    } finally {
      if (mounted) setState(() => _signingTodo = null);
    }
  }

  HomeScheduleRoute? _calendarRoute;
  final _supplements = <HomeSupplement, FeatureResult>{};
  final _loading = <HomeSupplement>{};
  int _generation = 0;
  List<Object?>? _todoInputs;
  List<HomeTodo> _todos = const [];
  bool uiScheduled = false;
  int? _gradeCheckEpoch;
  late final Timer _clock;
  late DateTime _now = (widget.homeClock ?? clock).now();
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && widget.visible) {
        setState(() => _now = (widget.homeClock ?? clock).now());
      }
    });
  }

  @override
  void didUpdateWidget(covariant HomeView old) {
    super.didUpdateWidget(old);
    if (old.cacheEpoch != widget.cacheEpoch ||
        old.businessCacheEpoch != widget.businessCacheEpoch) {
      _generation++;
      _showAllTodos = false;
      _supplements.clear();
      _loading.clear();
    }
    if (!old.visible && widget.visible)
      _now = (widget.homeClock ?? clock).now();
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  void _scheduleLoads() {
    if (uiScheduled || !widget.visible || widget.onLoadSupplement == null)
      return;
    final needed = HomeSupplement.values
        .where((s) => !_supplements.containsKey(s) && !_loading.contains(s))
        .toList();
    if (needed.isEmpty) return;
    uiScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      uiScheduled = false;
      if (mounted && widget.visible) {
        for (final source in needed) {
          unawaited(_load(source));
        }
      }
    });
  }

  Future<void> _load(HomeSupplement source, {bool force = false}) async {
    final load = widget.onLoadSupplement;
    if (load == null || _loading.contains(source)) return;
    final generation = _generation;
    setState(() => _loading.add(source));
    FeatureResult result;
    try {
      result = await load(source, force);
    } on Object {
      result = const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.internalError,
          title: '加载失败',
          message: '待办来源读取失败',
        ),
      );
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading.remove(source);
      final previous = _supplements[source];
      _supplements[source] =
          result.error != null &&
              result.details.isEmpty &&
              previous != null &&
              (previous.details.isNotEmpty ||
                  previous.overview != null ||
                  previous.evidence != null)
          ? FeatureResult.partial(
              error: result.error!,
              details: previous.details,
              overview: previous.overview,
              pagination: previous.pagination,
              resolvedRoute: previous.resolvedRoute,
              evidence: previous.evidence,
            )
          : result;
    });
  }

  Map<FeatureId, FeatureSnapshot> _sources() {
    final sources = Map<FeatureId, FeatureSnapshot>.of(widget.snapshots);
    for (final (source, feature, view) in [
      (
        HomeSupplement.bykcChosen,
        FeatureId.bykc,
        FeatureQueryView.bykcChosenCourses,
      ),
      (HomeSupplement.cgyyOrders, FeatureId.cgyy, FeatureQueryView.cgyyOrders),
    ]) {
      final result = _supplements[source];
      final saved = sources[feature];
      if (saved?.evidence != null &&
          saved?.readContext?.query?.view == view &&
          (result == null ||
              (result.error != null &&
                  result.details.isEmpty &&
                  result.overview == null))) {
        sources[feature] = saved!.copyWith(
          status: _loading.contains(source)
              ? FeatureLoadStatus.loading
              : FeatureLoadStatus.stale,
          error: result?.error,
          clearError: result?.error == null,
        );
        continue;
      }
      sources[feature] = FeatureSnapshot(
        feature: feature,
        status: _loading.contains(source)
            ? FeatureLoadStatus.loading
            : result == null
            ? FeatureLoadStatus.idle
            : result.error != null
            ? (result.details.isNotEmpty || result.overview != null
                  ? FeatureLoadStatus.stale
                  : FeatureLoadStatus.failure)
            : result.evidence?.complete == false ||
                  result.evidence?.origin == DataOrigin.persisted
            ? FeatureLoadStatus.stale
            : result.isEmpty
            ? FeatureLoadStatus.empty
            : FeatureLoadStatus.success,
        details: result?.details ?? const [],
        overview: result?.overview,
        evidence: result?.evidence,
        updatedAt:
            result?.evidence?.fetchedAt ??
            (result != null && result.error == null ? _now : null),
        error: result?.error,
        resolvedRoute: result?.resolvedRoute,
        pagination: result?.pagination,
        readContext: FeatureReadContext(
          requestRevision: widget.cacheEpoch,
          query: FeatureQuery(view: view),
        ),
      );
    }
    return sources;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleLoads();
    if (widget.visible &&
        widget.onCheckGradeUpdates != null &&
        _gradeCheckEpoch != widget.cacheEpoch) {
      final epoch = widget.cacheEpoch;
      _gradeCheckEpoch = epoch;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible && widget.cacheEpoch == epoch) {
          unawaited(widget.onCheckGradeUpdates!());
        } else if (mounted && _gradeCheckEpoch == epoch) {
          _gradeCheckEpoch = null;
        }
      });
    }
    final schedule = widget.snapshots[FeatureId.schedule]!;
    final campusNow = homeCampusTime(_now);
    final sources = _sources();

    final weeks =
        _supplements[HomeSupplement.currentWeek]?.details
            .map((d) => d.presentation)
            .whereType<WeekPresentation>()
            .toList() ??
        [];
    final week = weeks.length == 1 ? weeks.single : null;
    final reminder = widget.reminderSettings;
    // 课表、路线和成绩通知更新不改变待办；只在来源或时间变化时重新投影。
    final todoInputs = <Object?>[
      for (final feature in [
        FeatureId.bykc,
        FeatureId.cgyy,
        FeatureId.spoc,
        FeatureId.judge,
        FeatureId.signin,
        FeatureId.ygdk,
        FeatureId.exam,
      ])
        widget.snapshots[feature],
      for (final source in HomeSupplement.values) _supplements[source],
      _loading.contains(HomeSupplement.bykcChosen),
      _loading.contains(HomeSupplement.cgyyOrders),
      _now,
      reminder?.enabled,
      reminder?.weekDoneKey,
      reminder?.termDoneKey,
    ];
    if (!listEquals(_todoInputs, todoInputs)) {
      _todoInputs = todoInputs;
      _todos = buildHomeTodos(
        snapshots: sources,
        now: campusNow,
        currentWeek: week,
        ygdkReminderEnabled: reminder?.enabled ?? false,
        ygdkWeekDone:
            week != null &&
            reminder?.weekDoneKey == '${week.responseTerm}:${week.number}',
        ygdkTermDone:
            week != null && reminder?.termDoneKey == week.responseTerm,
      );
    }
    final tasks = _todos
        .where((task) => !_completedSignins.contains(_signinKey(task)))
        .toList();
    final overview = sources[FeatureId.ygdk]?.overview;
    if (widget.visible &&
        week != null &&
        overview is YgdkOverview &&
        sources[FeatureId.ygdk]?.status == FeatureLoadStatus.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible)
          widget.onObserveProgress?.call(week, overview);
      });
    }
    const features = [
      FeatureId.bykc,
      FeatureId.spoc,
      FeatureId.judge,
      FeatureId.cgyy,
      FeatureId.signin,
      FeatureId.ygdk,
      FeatureId.exam,
    ];
    final loading = features
        .where((f) => sources[f]?.status == FeatureLoadStatus.loading)
        .toList();
    final failed = features
        .where(
          (f) =>
              sources[f]?.status == FeatureLoadStatus.failure ||
              (sources[f]?.status == FeatureLoadStatus.stale &&
                  sources[f]?.error != null),
        )
        .toList();
    final courseSection = HomeScheduleSection(
      today: schedule,
      weekResult: _supplements[HomeSupplement.currentWeek],
      now: campusNow,
      visible: widget.visible,
      epoch: widget.cacheEpoch,
      businessEpoch: widget.businessCacheEpoch,
      onLoadDay: widget.onLoadDaySchedule,
      onRoute: (value) {
        if (mounted && value != _calendarRoute)
          setState(() => _calendarRoute = value);
      },
      onOpenSchedule: () => widget.onFeatureTap(FeatureId.schedule),
    );
    final todoSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题字号与“今日课表”一致；加载提示紧跟标题，不占用右侧位置。
        Row(
          children: [
            Text(
              '待办区',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (loading.any(
              (f) => sources[f]?.status == FeatureLoadStatus.loading,
            )) ...[
              const SizedBox(width: 8),
              const SizedBox.square(
                dimension: 20,
                child: Center(child: LoadingGlyph()),
              ),
            ],
            const Spacer(),
            if (tasks.length > 4)
              TextButton(
                key: const ValueKey('home-todos-toggle'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                onPressed: () => setState(() => _showAllTodos = !_showAllTodos),
                child: Text(_showAllTodos ? '收起' : '查看全部（${tasks.length}）'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        HomeTodoGrid(
          key: const ValueKey('home-todos'),
          children: [
            for (final task in _showAllTodos ? tasks : tasks.take(4))
              _HomeTodoCard(
                item: task,
                now: campusNow,
                onTap: () => widget.onTodoTap(task),
                signing: _signingTodo == task.id,
                signinUncertain: _uncertainSignins.contains(_signinKey(task)),
                onSignin:
                    _signingTodo == null &&
                        task.signinAction != null &&
                        widget.onSignin != null &&
                        !_uncertainSignins.contains(_signinKey(task))
                    ? () => _signin(task)
                    : null,
                onRefreshSignin: _signingTodo == null
                    ? () => _refreshSignin(task)
                    : null,
              ),
          ],
        ),
        if (tasks.isEmpty && loading.isNotEmpty)
          const LoadingPlaceholder(compact: true)
        else if (tasks.isEmpty &&
            features.any((f) => sources[f]?.status == FeatureLoadStatus.idle))
          const SizedBox(height: 120)
        else if (tasks.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(failed.isNotEmpty ? '已加载的来源中暂无近期待办' : '当前没有待办'),
            ),
          ),
        if (failed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '部分内容加载失败：${failed.map(_homeLabel).join('、')}，已显示其余待办。',
            ),
          ),
        for (final feature in features)
          if (sources[feature]?.evidence?.cacheFailure case final failure?
              when !failed.contains(feature) &&
                  sources[feature]?.status != FeatureLoadStatus.loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_homeLabel(feature)}：${uiCacheReadFailureText(failure)}',
              ),
            ),
        if (_supplements[HomeSupplement.currentWeek] case final result?
            when result.error != null &&
                !_loading.contains(HomeSupplement.currentWeek))
          Row(
            children: [
              const Expanded(child: Text('当前周次未确定，暂不显示阳光提醒')),
              TextButton(
                onPressed: () => _load(HomeSupplement.currentWeek, force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        for (final feature in failed)
          ListTile(
            dense: true,
            title: Text(
              '${_homeLabel(feature)}：${_homeSummary(sources[feature]!)}',
            ),
            trailing: TextButton(
              onPressed: () => feature == FeatureId.bykc
                  ? _load(HomeSupplement.bykcChosen, force: true)
                  : feature == FeatureId.cgyy
                  ? _load(HomeSupplement.cgyyOrders, force: true)
                  : widget.onRetryFeature(feature),
              child: const Text('重试'),
            ),
          ),
      ],
    );
    Widget shortcuts(String title, List<FeatureId> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        UiSectionTitle(title),
        _HomeCardGrid(
          maxColumns: 4,
          minWidth: 156,
          children: [
            for (final feature in items)
              _HomeShortcutCard(
                feature: feature,
                onTap: () => widget.onFeatureTap(feature),
              ),
          ],
        ),
      ],
    );
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        key: const ValueKey('home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(
          UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
        ),
        children: [
          if (widget.writeReadbackNotice case final notice?) ...[
            notice,
            const SizedBox(height: 12),
          ],
          if (widget.gradeScoreNotice case final notice?) ...[
            GradeScoreBanner(
              notice: notice,
              onOpen: widget.onOpenGradeNotice,
              onDismiss: widget.onDismissGradeNotice,
            ),
            const SizedBox(height: 12),
          ],
          courseSection,
          // 课程卡片自带 12 的下边距，再留 12 与卡片间距相称。
          const SizedBox(height: 12),
          todoSection,
          if (widget.recentFeatures.isNotEmpty)
            shortcuts('最近使用', widget.recentFeatures.take(4).toList()),
        ],
      ),
    );
  }
}

String _homeLabel(FeatureId feature) => switch (feature) {
  FeatureId.exam => '考试',
  FeatureId.bykc => '博雅',
  FeatureId.spoc => 'SPOC',
  FeatureId.judge => '希冀',
  FeatureId.cgyy => '研讨室',
  FeatureId.signin => '签到',
  FeatureId.ygdk => '阳光打卡',
  _ => feature.title,
};

String uiCacheReadFailureText(CacheMaintenanceFailure failure) =>
    failure == CacheMaintenanceFailure.capacity
    ? '本机空间不足，在线内容已显示，暂未保存到本机。'
    : '在线内容已显示，暂未保存到本机。';

String _homeSummary(FeatureSnapshot snapshot) =>
    snapshot.error?.message ?? '加载失败，请重试';

class _HomeTodoCard extends StatelessWidget {
  const _HomeTodoCard({
    required this.item,
    required this.now,
    required this.onTap,
    this.onSignin,
    this.onRefreshSignin,
    this.signing = false,
    this.signinUncertain = false,
  });
  final HomeTodo item;
  final DateTime now;
  final VoidCallback onTap;
  final Future<void> Function()? onSignin, onRefreshSignin;
  final bool signing, signinUncertain;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = item.feature == FeatureId.signin && signing
        ? '签到处理中'
        : signinUncertain
        ? '结果待确认'
        : item.statusLabel;
    return Card(
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: item.feature == FeatureId.signin
            ? (signing ? null : onSignin ?? onRefreshSignin)
            : item.navigation == null
            ? null
            : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 类型标签与标题同一行；“待××”与时间信息重复，不再单独显示。
                        Row(
                          children: [
                            _homeChip(
                              context,
                              _homeLabel(item.feature),
                              accented: true,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            // 状态紧跟标题；“待××”与时间信息重复，不显示。
                            if (!status.startsWith('待')) ...[
                              const SizedBox(width: 6),
                              _homeChip(context, status),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                    ),
                    Text(
                      item.timeLabel,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: item.isSoonAt(now)
                            ? (theme.brightness == Brightness.dark
                                  ? const Color(0xFFFFBD75)
                                  : const Color(0xFF9A4D00))
                            : theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              if (item.feature == FeatureId.signin) ...[
                const SizedBox(width: 8),
                Center(
                  child: FilledButton(
                    onPressed: signing ? null : onSignin ?? onRefreshSignin,
                    child: Text(
                      signing
                          ? '处理中…'
                          : onSignin != null
                          ? '签到'
                          : '刷新状态',
                    ),
                  ),
                ),
              ] else if (item.navigation != null)
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeChip(BuildContext context, String text, {bool accented = false}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accented
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (accented) ...[
            Icon(
              uiFeatureIcon(item.feature),
              size: 16,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: accented
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class FeatureGridView extends StatelessWidget {
  const FeatureGridView({
    required this.snapshots,
    required this.onFeatureTap,
    required this.onRetryFeature,
    required this.features,
    this.onOpenIhome,
  });
  final Map<FeatureId, FeatureSnapshot> snapshots;
  final ValueChanged<FeatureId> onFeatureTap;
  final Future<void> Function(FeatureId) onRetryFeature;
  final List<FeatureId> features;
  final VoidCallback? onOpenIhome;

  @override
  Widget build(BuildContext context) => CustomScrollView(
    slivers: [
      SliverPadding(
        padding: EdgeInsets.all(
          UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
        ),
        sliver: SliverList.list(
          children: [
            if (onOpenIhome != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UiEntryCard(
                  title: 'iHome',
                  icon: Icons.forum_outlined,
                  subtitle: '校园诉求、回复与公告',
                  onTap: onOpenIhome!,
                ),
              ),
            for (final feature in features)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  container: true,
                  button: true,
                  excludeSemantics: true,
                  onTap: () => onFeatureTap(feature),
                  label:
                      '${feature.title}：${snapshots[feature]?.summary ?? feature.description}。点击查看详情',
                  child: UiEntryCard(
                    title: feature.title,
                    icon: uiFeatureIcon(feature),
                    subtitle: feature.description,
                    onTap: () => onFeatureTap(feature),
                  ),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// 卡片只负责排布，滚动统一交给首页；每行按内容自然增高。
class _HomeCardGrid extends StatelessWidget {
  const _HomeCardGrid({
    required this.children,
    required this.maxColumns,
    required this.minWidth,
  });
  final List<Widget> children;
  final int maxColumns;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = ((constraints.maxWidth + 12) / (minWidth * scale + 12))
          .floor()
          .clamp(1, maxColumns);
      return Column(
        children: [
          for (var start = 0; start < children.length; start += columns) ...[
            if (start > 0) const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var column = 0; column < columns; column++) ...[
                    if (column > 0) const SizedBox(width: 12),
                    Expanded(
                      child: start + column < children.length
                          ? children[start + column]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _HomeShortcutCard extends StatelessWidget {
  const _HomeShortcutCard({required this.feature, required this.onTap});
  final FeatureId feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(uiFeatureIcon(feature), color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(feature.title, style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
