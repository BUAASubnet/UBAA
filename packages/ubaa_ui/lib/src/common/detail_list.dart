part of '../widgets.dart';

/// 详情列表的本地筛选只作用于 bridge 白名单字段。
class _FeatureDetailList extends StatefulWidget {
  const _FeatureDetailList({
    required this.feature,
    required this.details,
    this.pagination,
    this.query,
    this.onQuery,
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
  });

  final FeatureId feature;
  final List<FeatureDetail> details;
  final FeaturePagination? pagination;
  final FeatureQuery? query;
  final Future<void> Function(FeatureQuery query)? onQuery;
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

  @override
  State<_FeatureDetailList> createState() => _FeatureDetailListState();
}

class _FeatureDetailListState extends State<_FeatureDetailList> {
  static const _pageSize = 20;
  final TextEditingController _queryController = TextEditingController();
  final Set<String> _selectedEvaluationKeys = <String>{};
  String _query = '';
  int _page = 0;

  @override
  void didUpdateWidget(covariant _FeatureDetailList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final validKeys = <String>{
      for (final detail in widget.details)
        if (_evaluationSubmitTarget(detail) case final target?)
          target.selectionKey,
    };
    _selectedEvaluationKeys.removeWhere((key) => !validKeys.contains(key));
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final details = query.isEmpty
        ? widget.details
        : widget.details
              .where((detail) {
                final values = <String>[
                  detail.title,
                  if (detail.subtitle case final subtitle?) subtitle,
                  for (final field in detail.fields) ...<String>[
                    field.label,
                    field.value,
                  ],
                ];
                return values.any(
                  (value) => value.toLowerCase().contains(query),
                );
              })
              .toList(growable: false);
    final serverPagination = widget.pagination;
    final pageCount = serverPagination == null
        ? details.isEmpty
              ? 0
              : (details.length + _pageSize - 1) ~/ _pageSize
        : 1;
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final start = page * _pageSize;
    final visible = serverPagination == null
        ? details.skip(start).take(_pageSize).toList(growable: false)
        : details;
    final pendingEvaluationsByKey = <String, EvaluationSubmitTarget>{};
    for (final detail in widget.details) {
      if (_evaluationSubmitTarget(detail) case final target?) {
        pendingEvaluationsByKey.putIfAbsent(target.selectionKey, () => target);
      }
    }
    final pendingEvaluations = pendingEvaluationsByKey.values.toList(
      growable: false,
    );
    final selectedEvaluations = pendingEvaluations
        .where(
          (target) => _selectedEvaluationKeys.contains(target.selectionKey),
        )
        .toList(growable: false);
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: '筛选详情',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() {
              _query = value;
              _page = 0;
            }),
          ),
        ),
        ..._evaluationBatchFields(
          setState,
          pendingEvaluations,
          selectedEvaluations,
        ),
        Expanded(
          child: details.isEmpty
              ? const Center(child: Text('没有匹配的详情'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final detail = visible[index];
                    final courseId = _courseId(detail);
                    final bykcSelectAction = detail.action<BykcSelectAction>();
                    final bykcDeselectAction = detail
                        .action<BykcDeselectAction>();
                    final bykcSignInAction = _bykcSignAction(
                      detail,
                      BykcSignKind.signIn,
                    );
                    final bykcSignOutAction = _bykcSignAction(
                      detail,
                      BykcSignKind.signOut,
                    );
                    final signinAction = detail.action<SigninPerformAction>();
                    final cgyyCancelAction = _cgyyCancelAction(detail);
                    final libbookReserveAction = detail
                        .action<LibbookReserveAction>();
                    final libbookCancelAction = detail
                        .action<LibbookCancelAction>();
                    final cgyyReservation = _cgyyReserveAction(detail);
                    final evaluation = _evaluationSubmitTarget(detail);
                    final ygdkAction = _ygdkAction(detail);
                    final canBykcSign =
                        bykcSignInAction?.eligibility ==
                        ActionEligibility.allowed;
                    final canBykcSignOut =
                        bykcSignOutAction?.eligibility ==
                        ActionEligibility.allowed;
                    final canBykcSelect =
                        bykcSelectAction?.eligibility ==
                        ActionEligibility.allowed;
                    final canBykcDeselect =
                        bykcDeselectAction?.eligibility ==
                        ActionEligibility.allowed;
                    final canSignin =
                        signinAction?.eligibility ==
                            ActionEligibility.allowed &&
                        signinAction!.scheduleId.trim().isNotEmpty;
                    final canLibbookReserve =
                        libbookReserveAction?.eligibility ==
                            ActionEligibility.allowed &&
                        <String>[
                          libbookReserveAction!.areaId,
                          libbookReserveAction.seatId,
                          libbookReserveAction.day,
                          libbookReserveAction.segment,
                          libbookReserveAction.startTime,
                          libbookReserveAction.endTime,
                        ].every((value) => value.trim().isNotEmpty);
                    final canLibbookCancel =
                        libbookCancelAction?.eligibility ==
                            ActionEligibility.allowed &&
                        libbookCancelAction!.bookingId.trim().isNotEmpty &&
                        libbookCancelAction.page > 0 &&
                        libbookCancelAction.limit > 0;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              detail.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (detail.subtitle case final subtitle?
                                when subtitle.trim().isNotEmpty) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            for (final field in detail.fields) ...<Widget>[
                              const SizedBox(height: 8),
                              _DetailField(
                                label: field.label,
                                value: field.value,
                              ),
                            ],
                            ..._evaluationSelectionFields(setState, evaluation),
                            ..._bykcCourseWriteFields(
                              context,
                              courseId,
                              bykcSelectAction,
                              bykcDeselectAction,
                              canBykcSelect,
                              canBykcDeselect,
                            ),
                            ..._bykcSignWriteFields(
                              context,
                              bykcSignInAction,
                              bykcSignOutAction,
                              canBykcSign,
                              canBykcSignOut,
                            ),
                            ..._signinWriteFields(
                              context,
                              signinAction,
                              canSignin,
                            ),
                            ..._libbookCancelWriteFields(
                              context,
                              libbookCancelAction,
                              canLibbookCancel,
                            ),
                            ..._cgyyCancelWriteFields(cgyyCancelAction),
                            ..._libbookReserveWriteFields(
                              context,
                              libbookReserveAction,
                              canLibbookReserve,
                            ),
                            ..._evaluationSubmitFields(evaluation),
                            ..._cgyyReserveWriteFields(
                              context,
                              cgyyReservation,
                            ),
                            ..._ygdkWriteFields(context, ygdkAction, detail),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        ..._paginationFields(setState, serverPagination, pageCount, page),
      ],
    );
  }
}
