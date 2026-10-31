import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../common/section.dart';
import '../features/home/schedule.dart';
import '../features/home/todo_grid.dart';
import '../shared/loading.dart' show LoadingPlaceholder;
import '../features/grades/notice.dart' show GradeScoreBanner;
import '../shared/feature_icons.dart' show uiFeatureIcon;

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
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
    this.onSyncStatus,
    this.onPullRefresh,
    this.deferSupplements = false,
  });
  final Clock? homeClock;
  final List<FeatureId> recentFeatures;

  /// 上报首页全部来源（含博雅已选、研讨室订单）是否刷新中及最早更新时间，供标题栏显示。
  final void Function(bool busy, DateTime? updatedAt)? onSyncStatus;

  /// 包装下拉触发的刷新，让外层知道这次刷新已有下拉指示器。
  final Future<void> Function(Future<void> Function() refresh)? onPullRefresh;

  /// 会话恢复期间暂缓补充来源，等首页刷新一起开始，避免排队后被刷新取消再重排。
  final bool deferSupplements;
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
  State<HomeView> createState() => HomeViewState();
}

class HomeViewState extends State<HomeView> {
  /// 首页显示的全部来源；应用层刷新前 6 项，博雅与研讨室由本页作为补充来源读取。
  static const _syncedFeatures = [
    FeatureId.schedule,
    FeatureId.signin,
    FeatureId.spoc,
    FeatureId.judge,
    FeatureId.ygdk,
    FeatureId.exam,
    FeatureId.bykc,
    FeatureId.cgyy,
  ];
  (bool, DateTime?)? _reportedSync;

  /// 下拉、标题栏按钮或快捷键刷新：应用层来源与两个补充来源一起强制重读。
  /// 主来源先推进读取代次，再发出补充请求，避免新请求立即被旧代次取消。
  ///
  /// 全部来源都拿到可显示结果（只剩希冀等后台补全细节）即视为刷新完成，
  /// 下拉指示器不再等待后台补全结束。
  Future<void> refresh() {
    final settled = Completer<void>();
    _refreshSettled = settled;
    _sawBusy = false;
    final core = widget.onRefresh();
    final supplements = Future.wait([
      _load(HomeSupplement.bykcChosen, force: true),
      _load(HomeSupplement.cgyyOrders, force: true),
    ]);
    return Future.wait([
      supplements,
      Future.any([core, settled.future]),
    ]).whenComplete(() {
      if (identical(_refreshSettled, settled)) _refreshSettled = null;
    });
  }

  Completer<void>? _refreshSettled;
  bool _sawBusy = false;

  void _reportSync(Map<FeatureId, FeatureSnapshot> sources) {
    final report = widget.onSyncStatus;

    var busy = false;
    DateTime? oldest;
    for (final feature in _syncedFeatures) {
      final snapshot = sources[feature];
      if (snapshot == null) continue;
      // 已发布首批结果、后台补全细节时不算刷新中。
      busy |=
          snapshot.status == FeatureLoadStatus.loading && !snapshot.refining;
      final at = snapshot.updatedAt;
      if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    }
    // 刷新开始后先见到“刷新中”，再变为不忙，才算本次刷新已出结果。
    if (_refreshSettled case final settled? when !settled.isCompleted) {
      final coreBusy = _syncedFeatures.take(6).any((feature) {
        final snapshot = sources[feature];
        return snapshot?.status == FeatureLoadStatus.loading &&
            !(snapshot?.refining ?? false);
      });
      if (coreBusy) {
        _sawBusy = true;
      } else if (_sawBusy) {
        settled.complete();
      }
    }
    final next = (busy, oldest);
    if (report == null || next == _reportedSync) return;
    _reportedSync = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _reportedSync == next) report(busy, oldest);
    });
  }

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
  final _pending = <HomeSupplement, Future<void>>{};
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
    if (old.businessCacheEpoch != widget.businessCacheEpoch) {
      // 本机缓存被清理：在途结果和已显示内容都作废。
      _generation++;
      _showAllTodos = false;
      _supplements.clear();
      _loading.clear();
      _pending.clear();
    } else if (old.cacheEpoch != widget.cacheEpoch) {
      // 读取代次变化（如首页刷新开始）：在途请求刚发出，结果继续采用，避免启动时整轮重发；
      // 未在途的来源保留旧内容并重新读取。换账号时 Shell 会重建本页，不走这里。
      final idle = HomeSupplement.values
          .where((s) => !_loading.contains(s))
          .toList();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.visible || widget.deferSupplements) return;
        for (final source in idle) {
          if (!_loading.contains(source)) unawaited(_load(source));
        }
      });
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
    if (uiScheduled ||
        !widget.visible ||
        widget.deferSupplements ||
        widget.onLoadSupplement == null)
      return;
    final needed = HomeSupplement.values
        .where((s) => !_supplements.containsKey(s) && !_loading.contains(s))
        .toList();
    if (needed.isEmpty) return;
    uiScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      uiScheduled = false;
      if (mounted && widget.visible && !widget.deferSupplements) {
        for (final source in needed) {
          unawaited(_load(source));
        }
      }
    });
  }

  Future<void> _load(HomeSupplement source, {bool force = false}) {
    final pending = _pending[source];
    if (pending != null) return pending;
    late final Future<void> task;
    task = _readSupplement(source, force: force).whenComplete(() {
      if (identical(_pending[source], task)) _pending.remove(source);
    });
    _pending[source] = task;
    return task;
  }

  Future<void> _readSupplement(
    HomeSupplement source, {
    bool force = false,
  }) async {
    final load = widget.onLoadSupplement;
    if (load == null) return;
    final generation = _generation;
    final epoch = widget.cacheEpoch;
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
    if (result.error != null && epoch != widget.cacheEpoch) {
      // 读取代次在途中变化导致的取消或失败不显示，直接按新代次重读。
      setState(() => _loading.remove(source));
      if (widget.visible && !widget.deferSupplements) {
        await _readSupplement(source, force: force);
      }
      return;
    }
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
    _reportSync(sources);

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
      trailing: widget.recentFeatures.isEmpty
          ? null
          : _RecentFeatureIcons(
              features: widget.recentFeatures.take(4).toList(),
              onTap: widget.onFeatureTap,
            ),
    );
    final todoSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 标题字号与“今日课表”一致；刷新状态统一显示在标题栏右侧。
        Row(
          children: [
            Text(
              '待办区',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
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
    return RefreshIndicator(
      onRefresh: () => widget.onPullRefresh?.call(refresh) ?? refresh(),
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

/// 最近使用的功能：今日课表标题右侧的一排小图标，长按显示名称。
class _RecentFeatureIcons extends StatelessWidget {
  const _RecentFeatureIcons({required this.features, required this.onTap});
  final List<FeatureId> features;
  final ValueChanged<FeatureId> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, feature) in features.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          IconButton.filledTonal(
            key: ValueKey('recent-${feature.name}'),
            tooltip: feature.title,
            style: IconButton.styleFrom(
              minimumSize: const Size(36, 36),
              fixedSize: const Size(36, 36),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
            ),
            iconSize: 18,
            onPressed: () => onTap(feature),
            icon: Icon(uiFeatureIcon(feature)),
          ),
        ],
      ],
    );
  }
}
