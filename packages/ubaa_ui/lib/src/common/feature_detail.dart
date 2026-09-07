part of '../widgets.dart';

class _FeatureDetailView extends StatelessWidget {
  const _FeatureDetailView({
    required this.feature,
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
  });

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

  @override
  Widget build(BuildContext context) {
    final showDetails =
        (snapshot.status == FeatureLoadStatus.success ||
            snapshot.status == FeatureLoadStatus.stale) &&
        snapshot.details.isNotEmpty;
    final content = Column(
      children: [
        if (snapshot.status == FeatureLoadStatus.stale)
          MaterialBanner(
            content: Text(snapshot.error?.message ?? '刷新失败，以下是上次成功加载的数据。'),
            leading: const Icon(Icons.sync_problem),
            actions: [
              TextButton(onPressed: () => onRetry(), child: const Text('重试')),
            ],
          ),
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
                switch (snapshot.status) {
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
    final page = Column(
      children: <Widget>[
        if (onQuery != null && _supportsQuery)
          _FeatureQueryControls(
            feature: feature,
            details: snapshot.details,
            onApply: onQuery!,
          ),
        if (snapshot.resolvedRoute case final route?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.route, size: 18),
                label: Text('实际路线：${route.label}'),
              ),
            ),
          ),
        Expanded(child: content),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回功能列表'),
            ),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // 短窗口或键盘出现时整页可滚动；不挤掉筛选与返回操作。
        // 详情列表仍有独立滚动位置，正常高度下外层没有滚动范围。
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final minimumHeight = 640.0 * (textScale < 1 ? 1.0 : textScale);
        return SingleChildScrollView(
          primary: false,
          child: SizedBox(
            height: constraints.maxHeight < minimumHeight
                ? minimumHeight
                : constraints.maxHeight,
            child: page,
          ),
        );
      },
    );
  }

  bool get _supportsQuery => switch (feature) {
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
      feature: feature,
      details: snapshot.details,
      pagination: snapshot.pagination,
      query: query,
      onQuery: onQuery,
      onBykcWrite: onBykcWrite,
      onBykcSignWrite: onBykcSignWrite,
      onSigninWrite: onSigninWrite,
      onCgyyCancelWrite: onCgyyCancelWrite,
      onLibbookReserveWrite: onLibbookReserveWrite,
      onLibbookCancelWrite: onLibbookCancelWrite,
      onCgyySubmitWrite: onCgyySubmitWrite,
      onEvaluationWrite: onEvaluationWrite,
      onYgdkSubmitWrite: onYgdkSubmitWrite,
      onPickYgdkPhoto: onPickYgdkPhoto,
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            _featureIcon(feature),
            size: 56,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('暂无${feature.title}数据'),
          if (snapshot.summary case final summary?
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
              snapshot.error ??
              const UiError(
                code: UbaaErrorCode.internalError,
                title: '加载失败',
                message: '暂时无法加载该功能，请稍后重试。',
                retryable: true,
              ),
          onRetry: () => onRetry(),
        ),
      ),
    ),
  );
}
