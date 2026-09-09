part of '../widgets.dart';

extension _CgyyWriteForm on _FeatureDetailListState {
  Future<void> _showCgyyReservationForm(
    BuildContext context,
    CgyyReserveAction target,
    List<CgyyReserveAction> availableActions,
  ) async {
    final original = widget.details;
    final input = await _collectCgyyReservation(
      context,
      target,
      availableActions,
      formContext: widget.cgyyFormContext,
    );
    if (input != null && mounted && identical(original, widget.details))
      await widget.onCgyySubmitWrite?.call(input);
  }
}

Future<CgyySubmitInput?> _collectCgyyReservation(
  BuildContext context,
  CgyyReserveAction target,
  List<CgyyReserveAction> availableActions, {
  _CgyyFormContext? formContext,
  List<CgyyReserveAction>? initialSelection,
  String? selectionLabel,
}) async {
  final data = formContext ?? _CgyyFormContext(draft: _CgyyFormDraft());
  final generation = data.draft.generation;
  final result = await Navigator.of(context).push<CgyySubmitInput>(
    MaterialPageRoute(
      builder: (_) => _CgyyReservationForm(
        target: target,
        availableActions: availableActions,
        data: data,
        initialSelection: initialSelection,
        selectionLabel: selectionLabel,
      ),
    ),
  );
  final valid = generation == data.draft.generation;
  if (formContext == null) data.draft.dispose();
  return valid ? result : null;
}

class _CgyyReservationForm extends StatefulWidget {
  const _CgyyReservationForm({
    required this.target,
    required this.availableActions,
    required this.data,
    this.initialSelection,
    this.selectionLabel,
  });
  final CgyyReserveAction target;
  final List<CgyyReserveAction> availableActions;
  final _CgyyFormContext data;
  final List<CgyyReserveAction>? initialSelection;
  final String? selectionLabel;
  @override
  State<_CgyyReservationForm> createState() => _CgyyReservationFormState();
}

class _CgyyReservationFormState extends State<_CgyyReservationForm> {
  late final _CgyyFormDraft draft = widget.data.draft;
  late final int generation;
  late final phone = TextEditingController(text: draft.phone),
      theme = TextEditingController(text: draft.theme),
      purpose = TextEditingController(text: draft.manualPurpose),
      people = TextEditingController(text: draft.people),
      content = TextEditingController(text: draft.content),
      joiners = TextEditingController(text: draft.joiners);
  late final actionsByKey = <String, CgyyReserveAction>{
    for (final a in [widget.target, ...widget.availableActions])
      _cgyyActionKey(a): a,
  };
  late final selected = <String>{
    for (final a in widget.initialSelection ?? [widget.target])
      _cgyyActionKey(a),
  };
  List<CgyyPurposePresentation> options = [];
  bool loading = false;
  UiError? loadError;
  ConnectionMode? purposeRoute;
  String? error;

  @override
  void initState() {
    super.initState();
    generation = draft.generation;
    draft.addListener(_invalidate);
    unawaited(_loadPurposes(false));
  }

  void _invalidate() {
    if (draft.generation == generation) return;
    // 清除或换路线后不允许旧表单留在新账号上；也关闭本表单的选择弹窗。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((r) => identical(r, route));
      navigator.pop();
    });
  }

  Future<void> _loadPurposes(bool force) async {
    final load = widget.data.loadPurposes;
    if (load == null || loading) return;
    setState(() {
      loading = true;
      loadError = null;
    });
    FeatureResult result;
    try {
      result = await load(force);
    } on Object {
      result = const FeatureResult.failure(
        UiError(
          code: UbaaErrorCode.networkError,
          title: '活动类型加载失败',
          message: '请稍后重试。',
        ),
      );
    }
    if (!mounted || generation != draft.generation) return;
    setState(() {
      loading = false;
      loadError = result.error;
      purposeRoute = result.resolvedRoute;
      final candidates = result.details
          .map((d) => d.presentation)
          .whereType<CgyyPurposePresentation>()
          .toList();
      options = candidates
          .where(
            (p) =>
                p.key > 0 &&
                candidates.where((other) => other.key == p.key).length == 1,
          )
          .toList();
      if (!options.any((p) => p.key == draft.purpose))
        draft.purpose = options.isEmpty ? null : options.first.key;
    });
  }

  @override
  void dispose() {
    draft.removeListener(_invalidate);
    for (final c in [phone, theme, purpose, people, content, joiners]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setManual(bool value) => setState(() => draft.manual = value);
  void _setPurpose(int value) => setState(() {
    draft.purpose = value;
    draft.manual = false;
  });

  void _continue() {
    if (generation != draft.generation) return;
    final parsedPurpose = draft.manual
        ? int.tryParse(purpose.text.trim())
        : draft.purpose;
    final count = int.tryParse(people.text.trim());
    if (selected.isEmpty ||
        phone.text.trim().isEmpty ||
        theme.text.trim().isEmpty ||
        content.text.trim().isEmpty ||
        joiners.text.trim().isEmpty ||
        parsedPurpose == null ||
        parsedPurpose <= 0 ||
        count == null ||
        count <= 0) {
      setState(() => error = '请选择时段并完整填写预约信息。');
      return;
    }
    final actions = selected.map((k) => actionsByKey[k]!).toList()
      ..sort((a, b) => a.timeOrdinal.compareTo(b.timeOrdinal));
    Navigator.of(context).pop(
      CgyySubmitInput(
        actions: actions,
        phone: phone.text.trim(),
        theme: theme.text.trim(),
        purposeType: parsedPurpose,
        joinerNum: count,
        activityContent: content.text.trim(),
        joiners: joiners.text.trim(),
        isPhilosophySocialSciences: draft.philosophy,
        isOffSchoolJoiner: draft.offSchool,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routes = <String, ConnectionMode>{
      if (widget.data.route case final r?) '已选时段': r,
      if (purposeRoute case final r?) '活动类型': r,
    };
    final values = routes.values.toSet();
    final route = values.length == 1 ? values.single : null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        toolbarHeight: 56,
        title: const Text(
          '填写研讨室预约信息',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          IconButton(
            tooltip: '实际路线：${values.length > 1 ? '混合' : route?.label ?? '未确定'}',
            icon: Icon(
              route == ConnectionMode.direct
                  ? Icons.lan_outlined
                  : route == ConnectionMode.webvpn
                  ? Icons.vpn_lock_outlined
                  : Icons.route_outlined,
            ),
            onPressed: () async {
              if (widget.data.onRouteOptions case final show?) {
                await show(routes);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 840),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _section('已选时段', [
                        Text(
                          widget.selectionLabel ??
                              '站点 ${widget.target.venueSiteId} · ${widget.target.reservationDate.trim()}\n空间 ${widget.target.spaceId} · 时段 ${widget.target.timeId}',
                        ),
                        if (widget.initialSelection == null &&
                            actionsByKey.length > 1)
                          Text('选择预约时段（已选 ${selected.length} 个）'),
                        if (widget.initialSelection == null &&
                            actionsByKey.length > 1)
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final entry in actionsByKey.entries)
                                FilterChip(
                                  label: Text(
                                    '空间 ${entry.value.spaceId} · 时段 ${entry.value.timeId}',
                                  ),
                                  selected: selected.contains(entry.key),
                                  onSelected: (value) => setState(() {
                                    if (!value) {
                                      selected.remove(entry.key);
                                    } else {
                                      _selectCgyyAction(
                                        selected,
                                        actionsByKey,
                                        entry.key,
                                      );
                                    }
                                  }),
                                ),
                            ],
                          ),
                      ]),
                      const SizedBox(height: 12),
                      _information(),
                      const SizedBox(height: 12),
                      _section('附加选项', [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: draft.philosophy,
                          title: const Text('哲学社会科学类活动'),
                          onChanged: (v) =>
                              setState(() => draft.philosophy = v ?? false),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: draft.offSchool,
                          title: const Text('含校外参与人'),
                          onChanged: (v) =>
                              setState(() => draft.offSchool = v ?? false),
                        ),
                      ]),
                    ],
                  ),
                ),
                if (error case final message?)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('返回修改时段'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _continue,
                          child: const Text('继续确认'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

void _selectCgyyAction(
  Set<String> selectedKeys,
  Map<String, CgyyReserveAction> actionsByKey,
  String nextKey,
) {
  final next = actionsByKey[nextKey]!;
  final current = selectedKeys
      .map((key) => actionsByKey[key]!)
      .toList(growable: false);
  if (current.length == 1 &&
      _sameCgyyTarget(current.single, next) &&
      (current.single.timeOrdinal - next.timeOrdinal).abs() == 1) {
    selectedKeys.add(nextKey);
    return;
  }
  selectedKeys
    ..clear()
    ..add(nextKey);
}

bool _sameCgyyTarget(CgyyReserveAction left, CgyyReserveAction right) =>
    left.venueSiteId == right.venueSiteId &&
    left.reservationDate.trim() == right.reservationDate.trim() &&
    left.spaceId == right.spaceId &&
    left.venueSpaceGroupId == right.venueSpaceGroupId;

String _cgyyActionKey(CgyyReserveAction action) =>
    '${action.venueSiteId}:${action.reservationDate.trim()}:${action.spaceId}:'
    '${action.venueSpaceGroupId ?? ''}:${action.timeId}:${action.timeOrdinal}';
