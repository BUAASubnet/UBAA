part of '../widgets.dart';

class _FeatureDetailView extends StatefulWidget {
  const _FeatureDetailView({
    required this.feature,
    this.isLanding = false,
    required this.snapshot,
    this.query,
    required this.onBack,
    required this.onRetry,
    this.onBykcWrite,
    this.onBykcSignWrite,
    this.onSigninWrite,
    this.onCgyyCancelWrite,
    this.onLibbookReserveWrite,
    this.onLibbookCancelWrite,
    this.onCgyySubmitWrite,
    this.onEvaluationWrite,
    this.onYgdkSubmitWrite,
    this.onPickYgdkPhoto,
    this.onQuery,
    this.onNavigate,
    this.backLabel = '返回功能列表',
    this.onLoadAcademicTerms,
    this.readCacheEpoch = 0,
    super.key,
  });

  final bool isLanding;
  final FeatureId feature;
  final FeatureSnapshot snapshot;
  final FeatureQuery? query;
  final VoidCallback onBack;
  final Future<void> Function() onRetry;
  final Future<void> Function(WriteOperation operation, int courseId)?
  onBykcWrite;
  final BykcSignStarter? onBykcSignWrite;
  final SigninStarter? onSigninWrite;
  final CgyyCancelStarter? onCgyyCancelWrite;
  final LibbookReserveStarter? onLibbookReserveWrite;
  final LibbookCancelStarter? onLibbookCancelWrite;
  final CgyyReservationStarter? onCgyySubmitWrite;
  final EvaluationSubmitStarter? onEvaluationWrite;
  final YgdkSubmitStarter? onYgdkSubmitWrite;
  final YgdkPhotoPicker? onPickYgdkPhoto;
  final Future<void> Function(FeatureQuery query)? onQuery;
  final Future<void> Function(FeatureReadNavigation)? onNavigate;
  final String backLabel;
  final Future<FeatureResult> Function(bool forceRefresh)? onLoadAcademicTerms;
  final int readCacheEpoch;

  @override
  State<_FeatureDetailView> createState() => _FeatureDetailViewState();
}

class _FeatureDetailViewState extends State<_FeatureDetailView> {
  final _queryKey = GlobalKey<_FeatureQueryControlsState>();
  final _searchController = TextEditingController();
  bool _panelOpen = false;

  void togglePanel() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _panelOpen = !_panelOpen);
  }

  @override
  void didUpdateWidget(covariant _FeatureDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.readCacheEpoch != widget.readCacheEpoch) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showDetails =
        (widget.snapshot.status == FeatureLoadStatus.success ||
            widget.snapshot.status == FeatureLoadStatus.stale) &&
        widget.snapshot.details.isNotEmpty;
    final defaultContent = widget.isLanding
        ? _FeatureLandingMenu(
            feature: widget.feature,
            onOpen: widget.onNavigate!,
          )
        : Column(
            children: [
              if (widget.snapshot.status == FeatureLoadStatus.stale)
                MaterialBanner(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.snapshot.error?.message ?? '刷新失败，请稍后重试。'),
                      const Text('以下为上次成功加载的数据。'),
                    ],
                  ),
                  leading: const Icon(Icons.sync_problem),
                  actions: [
                    TextButton(
                      onPressed: () => widget.onRetry(),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              if (widget.snapshot.overview case final overview?
                  when widget.snapshot.status == FeatureLoadStatus.success ||
                      widget.snapshot.status == FeatureLoadStatus.empty ||
                      widget.snapshot.status == FeatureLoadStatus.stale)
                _CourseworkOverview(overview: overview),
              Expanded(
                key: const ValueKey<String>('stable-detail-list'),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 同一列表始终保留State；明确空结果仍将details更新为空。
                    ExcludeFocus(
                      excluding: !showDetails,
                      child: TickerMode(
                        enabled: showDetails,
                        child: Offstage(
                          offstage: !showDetails,
                          child: _details(context),
                        ),
                      ),
                    ),
                    if (!showDetails)
                      switch (widget.snapshot.status) {
                        FeatureLoadStatus.loading => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        FeatureLoadStatus.failure => _error(context),
                        _ => _empty(context),
                      },
                  ],
                ),
              ),
            ],
          );
    final content =
        !widget.isLanding &&
            widget.feature == FeatureId.libbook &&
            (widget.query?.view ?? FeatureQueryView.summary) !=
                FeatureQueryView.libbookBookings
        ? _LibbookReservationFlow(
            snapshot: widget.snapshot,
            query: widget.query ?? const FeatureQuery(),
            cacheEpoch: widget.readCacheEpoch,
            filter: _searchController.text,
            fallback: defaultContent,
            onReserve: widget.onLibbookReserveWrite,
            onQuery: widget.onQuery == null
                ? null
                : (query) {
                    _queryKey.currentState?.adoptLibraryQuery(query);
                    return widget.onQuery!(query);
                  },
            onSeatQuery: (query) {
              _queryKey.currentState?.adoptLibraryQuery(query, clearDate: true);
              setState(() => _panelOpen = true);
            },
          )
        : !widget.isLanding &&
              widget.feature == FeatureId.cgyy &&
              {
                FeatureQueryView.summary,
                FeatureQueryView.cgyyDayInfo,
              }.contains(widget.query?.view ?? FeatureQueryView.summary)
        ? _CgyyReservationFlow(
            snapshot: widget.snapshot,
            query: widget.query ?? const FeatureQuery(),
            cacheEpoch: widget.readCacheEpoch,
            filter: _searchController.text,
            fallback: defaultContent,
            onRetry: widget.onRetry,
            onSubmit: widget.onCgyySubmitWrite,
            onQuery: widget.onQuery == null
                ? null
                : (query) {
                    _queryKey.currentState?.adoptCgyyQuery(query);
                    return widget.onQuery!(query);
                  },
          )
        : defaultContent;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = MediaQuery.sizeOf(context).width >= 600;
        return Stack(
          children: [
            Positioned.fill(child: content),
            if (_panelOpen)
              Positioned.fill(
                child: ModalBarrier(
                  color: Colors.black26,
                  onDismiss: togglePanel,
                  semanticsLabel: '关闭搜索与筛选',
                ),
              ),
            Align(
              alignment: wide ? Alignment.topRight : Alignment.bottomCenter,
              child: ExcludeFocus(
                excluding: !_panelOpen,
                child: Offstage(
                  offstage: !_panelOpen,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: wide ? 420 : constraints.maxWidth,
                      maxWidth: wide ? 420 : constraints.maxWidth,
                      maxHeight: constraints.maxHeight * .85,
                    ),
                    child: Material(
                      elevation: 8,
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            title: const Text('搜索与筛选'),
                            trailing: TextButton(
                              onPressed: togglePanel,
                              child: const Text('完成'),
                            ),
                          ),
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Column(
                                children: [
                                  if (!widget.isLanding)
                                    TextField(
                                      controller: _searchController,
                                      decoration: const InputDecoration(
                                        labelText: '筛选详情',
                                        prefixIcon: Icon(Icons.search),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  if (widget.onQuery != null && _supportsQuery)
                                    _FeatureQueryControls(
                                      key: _queryKey,
                                      feature: widget.feature,
                                      details: widget.snapshot.details,
                                      snapshot: widget.snapshot,
                                      initialQuery: widget.query,
                                      onLoadAcademicTerms:
                                          widget.onLoadAcademicTerms,
                                      readCacheEpoch: widget.readCacheEpoch,
                                      onApply: widget.onQuery!,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool get _supportsQuery => switch (widget.feature) {
    FeatureId.schedule ||
    FeatureId.exam ||
    FeatureId.grades ||
    FeatureId.classroom ||
    FeatureId.bykc ||
    FeatureId.libbook ||
    FeatureId.ygdk ||
    FeatureId.cgyy ||
    FeatureId.signin ||
    FeatureId.spoc ||
    FeatureId.judge ||
    FeatureId.evaluation => true,
  };

  Widget _details(BuildContext context) {
    return _FeatureDetailList(
      feature: widget.feature,
      details: widget.snapshot.details,
      filter: _searchController.text,
      pagination: widget.snapshot.pagination,
      query: widget.query ?? const FeatureQuery(),
      onQuery: widget.onQuery,
      onNavigate: widget.onNavigate,
      onBykcWrite: widget.onBykcWrite,
      onBykcSignWrite: widget.onBykcSignWrite,
      onSigninWrite: widget.onSigninWrite,
      onCgyyCancelWrite: widget.onCgyyCancelWrite,
      onLibbookReserveWrite: widget.onLibbookReserveWrite,
      onLibbookCancelWrite: widget.onLibbookCancelWrite,
      onCgyySubmitWrite: widget.onCgyySubmitWrite,
      onEvaluationWrite: widget.onEvaluationWrite,
      onYgdkSubmitWrite: widget.onYgdkSubmitWrite,
      onPickYgdkPhoto: widget.onPickYgdkPhoto,
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _featureIcon(widget.feature),
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('暂无${widget.feature.title}数据'),
          if (widget.snapshot.summary case final summary?
              when summary.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(summary, textAlign: TextAlign.center),
          ],
        ],
      ),
    ),
  );

  Widget _error(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: FriendlyErrorCard(
          error:
              widget.snapshot.error ??
              const UiError(
                code: UbaaErrorCode.internalError,
                title: '加载失败',
                message: '暂时无法加载该功能，请稍后重试。',
                retryable: true,
              ),
          onRetry: () => widget.onRetry(),
        ),
      ),
    ),
  );
}
