import 'dart:async';
import '../../shared/loading.dart' show LoadingGlyph;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/error_card.dart' show FriendlyErrorCard;
import 'draft.dart' show CgyyFormContext, CgyyFormDraft;
import '../forms/action_bar.dart' show FormActionBar;
part 'fields.dart';

Future<CgyySubmitInput?> uiCollectCgyyReservation(
  BuildContext context,
  CgyyReserveAction target,
  List<CgyyReserveAction> availableActions, {
  CgyyFormContext? formContext,
  List<CgyyReserveAction>? initialSelection,
  String? selectionLabel,
}) async {
  final data = formContext ?? CgyyFormContext(draft: CgyyFormDraft());
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
  final CgyyFormContext data;
  final List<CgyyReserveAction>? initialSelection;
  final String? selectionLabel;
  @override
  State<_CgyyReservationForm> createState() => _CgyyReservationFormState();
}

class _CgyyReservationFormState extends State<_CgyyReservationForm> {
  late final CgyyFormDraft draft = widget.data.draft;
  late final int generation;
  late final phone = TextEditingController(text: draft.phone),
      theme = TextEditingController(text: draft.theme),
      people = TextEditingController(text: draft.people),
      content = TextEditingController(text: draft.content),
      joiners = TextEditingController(text: draft.joiners);
  late final actionsByKey = <String, CgyyReserveAction>{
    for (final a in [widget.target, ...widget.availableActions])
      uiCgyyActionKey(a): a,
  };
  late final selected = <String>{
    for (final a in widget.initialSelection ?? [widget.target])
      uiCgyyActionKey(a),
  };
  List<CgyyPurposePresentation> options = [];
  bool loading = false;
  UiError? loadError;
  ConnectionMode? purposeRoute;
  String? error;
  CgyyReservationDefaults? defaults;
  bool _submitted = false;
  bool _purposeChosen = false;

  @override
  void initState() {
    super.initState();
    generation = draft.generation;
    draft.addListener(_invalidate);
    unawaited(_loadPurposes(false));
    unawaited(_loadDefaults());
  }

  Future<void> _loadDefaults() async {
    final load = widget.data.loadDefaults;
    if (load == null) return;
    CgyyReservationDefaults? value;
    try {
      value = await load();
    } on Object {
      return; // 记忆读取失败只影响默认值，不阻断预约。
    }
    if (!mounted || generation != draft.generation || value == null) return;
    final last = value;
    setState(() {
      defaults = last;
      _applyDefaultPurpose();
      if (!draft.philosophy && !draft.offSchool) {
        draft.philosophy = last.isPhilosophySocialSciences;
        draft.offSchool = last.isOffSchoolJoiner;
      }
    });
  }

  void _applyDefaultPurpose() {
    final last = defaults?.purposeType;
    if (!_purposeChosen && last != null && options.any((p) => p.key == last))
      draft.purpose = last;
  }

  void _refreshErrors() => setState(() {});

  /// 未改动的输入框按灰字默认值提交。
  String _value(TextEditingController controller, String fallback) {
    final text = controller.text.trim();
    return text.isEmpty ? fallback.trim() : text;
  }

  String get _peopleFallback {
    final last = defaults?.joinerNum.trim() ?? '';
    return last.isEmpty ? '1' : last;
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
      if (result.error != null && result.details.isEmpty && options.isNotEmpty)
        return;
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
      _applyDefaultPurpose();
    });
  }

  @override
  void dispose() {
    draft.removeListener(_invalidate);
    for (final c in [phone, theme, people, content, joiners]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setPurpose(int value) => setState(() {
    draft.purpose = value;
    _purposeChosen = true;
  });

  void _continue() {
    if (generation != draft.generation) return;
    final parsedPurpose = draft.purpose;
    final last = defaults ?? const CgyyReservationDefaults();
    final phoneValue = _value(phone, last.phone);
    final themeValue = _value(theme, last.theme);
    final peopleValue = _value(people, _peopleFallback);
    final contentValue = _value(content, last.activityContent);
    final joinersValue = _value(joiners, last.joiners);
    final count = int.tryParse(peopleValue);
    if (selected.isEmpty ||
        phoneValue.isEmpty ||
        themeValue.isEmpty ||
        contentValue.isEmpty ||
        joinersValue.isEmpty ||
        parsedPurpose == null ||
        parsedPurpose <= 0 ||
        count == null ||
        count <= 0) {
      setState(() {
        _submitted = true;
        error = selected.isEmpty ? '请选择预约时段。' : '请补全标红的信息。';
      });
      return;
    }
    if (widget.data.saveDefaults case final save?) {
      unawaited(
        save(
          CgyyReservationDefaults(
            phone: phoneValue,
            theme: themeValue,
            purposeType: parsedPurpose,
            joinerNum: peopleValue,
            activityContent: contentValue,
            joiners: joinersValue,
            isPhilosophySocialSciences: draft.philosophy,
            isOffSchoolJoiner: draft.offSchool,
          ),
        ).catchError((Object _) {}),
      );
    }
    final actions = selected.map((k) => actionsByKey[k]!).toList()
      ..sort((a, b) => a.timeOrdinal.compareTo(b.timeOrdinal));
    Navigator.of(context).pop(
      CgyySubmitInput(
        actions: actions,
        phone: phoneValue,
        theme: themeValue,
        purposeType: parsedPurpose,
        joinerNum: count,
        activityContent: contentValue,
        joiners: joinersValue,
        isPhilosophySocialSciences: draft.philosophy,
        isOffSchoolJoiner: draft.offSchool,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        toolbarHeight: 64,
        title: const Text(
          '填写预约信息',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      bottomNavigationBar: FormActionBar(
        child: Padding(
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
      ),
      body: SafeArea(
        top: false,
        bottom: false,
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
                          (widget.selectionLabel ??
                                  '站点 ${widget.target.venueSiteId} · ${widget.target.reservationDate.trim()}\n空间 ${widget.target.spaceId} · 时段 ${widget.target.timeId}')
                              .replaceAll('\n', ' · '),
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
                                      uiSelectCgyyAction(
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

void uiSelectCgyyAction(
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

String uiCgyyActionKey(CgyyReserveAction action) =>
    '${action.venueSiteId}:${action.reservationDate.trim()}:${action.spaceId}:'
    '${action.venueSpaceGroupId ?? ''}:${action.timeId}:${action.timeOrdinal}';
