import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../../shared/dialogs/form_page.dart';
import '../../shared/dialogs/sheet.dart' show showUiSheet, UiSheetBody;
import 'draft.dart' show YgdkFormContext, YgdkFormDraft, uiYgdkItemKey;
part 'form_ygdk_draft.dart';
part 'form_defaults.dart';

class _YgdkFormPage extends StatefulWidget {
  const _YgdkFormPage({
    required this.items,
    required this.onPickPhoto,
    this.onCapturePhoto,
    required this.data,
    this.initialAction,
  });
  final List<FeatureDetail> items;
  final YgdkPhotoPicker? onPickPhoto;
  final YgdkPhotoPicker? onCapturePhoto;
  final YgdkFormContext data;
  final YgdkSubmitAction? initialAction;
  @override
  State<_YgdkFormPage> createState() => _YgdkFormPageState();
}

class _YgdkFormPageState extends State<_YgdkFormPage> {
  static const _previewCacheWidth = 720, _previewCacheHeight = 480;
  late final YgdkFormDraft draft = widget.data.draft;
  late final int generation;
  late final _startController = TextEditingController(text: draft.start);
  late final _endController = TextEditingController(text: draft.end);
  late final _placeController = TextEditingController(text: draft.place);
  YgdkPhotoInput? _photo;
  Uint8List? _previewBytes;
  String? _error;
  bool _picking = false;

  List<FeatureDetail> get _validItems => widget.items.where((d) {
    final a = d.action<YgdkSubmitAction>();
    return a?.hasCanonicalTarget == true &&
        widget.items.where((other) {
              final b = other.action<YgdkSubmitAction>();
              return b != null && uiYgdkItemKey(a!) == uiYgdkItemKey(b);
            }).length ==
            1;
  }).toList();

  FeatureDetail? get _selected {
    for (final d in _validItems) {
      if (uiYgdkItemKey(d.action<YgdkSubmitAction>()!) == draft.itemKey)
        return d;
    }
    return null;
  }

  bool get _valid => mounted && generation == draft.generation;

  @override
  void initState() {
    super.initState();
    generation = draft.generation;
    if (widget.initialAction case final a?) draft.itemKey = uiYgdkItemKey(a);
    draft.addListener(_invalidate);
  }

  void _invalidate() {
    if (generation == draft.generation) return;
    _releasePhotoReferences();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      final navigator = Navigator.of(context);
      navigator.popUntil((r) => identical(r, route));
      navigator.pop();
    });
  }

  @override
  void dispose() {
    draft.removeListener(_invalidate);
    _releasePhotoReferences();
    for (final c in [_startController, _endController, _placeController]) {
      c.dispose();
    }
    super.dispose();
  }

  String _itemName(FeatureDetail detail) =>
      detail.presentation is YgdkItemPresentation
      ? (detail.presentation as YgdkItemPresentation).name
      : detail.title;

  Future<void> _chooseItem() async {
    final selected = await showUiSheet<FeatureDetail>(
      context,
      builder: (context) => UiSheetBody(
        title: '选择运动项目',
        children: [
          for (final d in widget.items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_itemName(d)),
              enabled: _validItems.contains(d),
              subtitle: _validItems.contains(d) ? null : const Text('当前不可提交'),
              onTap: () => Navigator.pop(context, d),
            ),
          if (widget.items.isEmpty) const Text('暂无可用运动项目'),
        ],
      ),
    );
    if (_valid && selected != null && _validItems.contains(selected)) {
      setState(
        () =>
            draft.itemKey = uiYgdkItemKey(selected.action<YgdkSubmitAction>()!),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return UiFormScaffold(
      title: '填写阳光打卡信息',
      onClose: _cancel,
      error: _error,
      secondary: TextButton(onPressed: _cancel, child: const Text('取消')),
      primary: FilledButton(
        onPressed: _picking ? null : _continue,
        child: const Text('提交打卡'),
      ),
      children: [
        _section('运动项目', description: '留空时使用默认运动项目', [
          OutlinedButton(
            onPressed: _chooseItem,
            child: Text(selected == null ? '选择运动项目' : _itemName(selected)),
          ),
        ]),
        _section('时间', description: '全部留空时自动生成一小时时间段', [
          // 够宽时开始、结束并排，窄屏上下排列。
          LayoutBuilder(
            builder: (context, constraints) {
              final start = _timeField(
                _startController,
                '开始时间',
                (v) => draft.start = v,
              );
              final end = _timeField(
                _endController,
                '结束时间',
                (v) => draft.end = v,
              );
              return constraints.maxWidth >= 420
                  ? Row(
                      children: [
                        Expanded(child: start),
                        const SizedBox(width: 12),
                        Expanded(child: end),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [start, const SizedBox(height: 12), end],
                    );
            },
          ),
        ]),
        _section('地点', [
          TextField(
            controller: _placeController,
            onChanged: (v) => draft.place = v,
            decoration: const InputDecoration(labelText: '打卡地点'),
          ),
        ]),
        _section('照片', description: '单张不超过 10 MB，不选时使用默认图片', [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _picking || widget.onPickPhoto == null
                      ? null
                      : _pickPhoto,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _photo == null ? '选择照片' : '已选择照片：${_photo!.fileName}',
                  ),
                ),
              ),
              if (widget.onCapturePhoto != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _picking
                        ? null
                        : () => _pickPhoto(capture: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('拍摄照片'),
                  ),
                ),
              ],
            ],
          ),
          if (_previewBytes case final bytes?) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  bytes,
                  key: const ValueKey<String>('ygdk-photo-preview'),
                  width: 180,
                  height: 120,
                  cacheWidth: _previewCacheWidth,
                  cacheHeight: _previewCacheHeight,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 180,
                    height: 72,
                    child: Center(child: Text('照片预览不可用，请重新选择')),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _picking
                    ? null
                    : () => setState(_releasePhotoReferences),
                icon: const Icon(Icons.delete_outline),
                label: const Text('清除照片'),
              ),
            ),
          ],
        ]),
        UiFormSection(
          padding: EdgeInsets.zero,
          children: [
            CheckboxListTile(
              value: draft.share,
              onChanged: (v) => setState(() => draft.share = v ?? false),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.share_outlined),
              title: const Text('分享到打卡广场'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children, {String? description}) =>
      UiFormSection(title: title, description: description, children: children);

  Future<void> _pickPhoto({bool capture = false}) async {
    final picker = capture ? widget.onCapturePhoto : widget.onPickPhoto;
    if (picker == null || _picking || !_valid) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await picker();
      if (!_valid || picked == null) return;
      setState(() {
        _releasePhotoReferences();
        _photo = picked;
        _previewBytes = Uint8List.fromList(picked.bytes);
      });
    } on Object {
      if (_valid) {
        setState(() => _error = '照片读取失败，请选择 10 MB 以内的图片并检查相册权限');
      }
    } finally {
      if (_valid) setState(() => _picking = false);
    }
  }

  void _showError(String message) => setState(() => _error = message);

  void _cancel() {
    _releasePhotoReferences();
    Navigator.of(context).pop();
  }

  void _releasePhotoReferences() {
    final bytes = _previewBytes;
    if (bytes != null)
      unawaited(
        ResizeImage(
          MemoryImage(bytes),
          width: _previewCacheWidth,
          height: _previewCacheHeight,
        ).evict(cache: PaintingBinding.instance.imageCache),
      );
    _previewBytes = null;
    _photo = null;
  }
}

extension YgdkFormTime on _YgdkFormPageState {
  Widget _timeField(
    TextEditingController controller,
    String label,
    ValueChanged<String> save,
  ) => TextField(
    controller: controller,
    onChanged: save,
    decoration: InputDecoration(
      labelText: label,
      hintText: 'YYYY-MM-DD HH:mm',
      suffixIcon: IconButton(
        tooltip: '选择$label',
        icon: const Icon(Icons.calendar_today_outlined),
        onPressed: () => _chooseTime(controller, label, save),
      ),
    ),
  );

  Future<void> _chooseTime(
    TextEditingController controller,
    String label,
    ValueChanged<String> save,
  ) async {
    final parsed = DateTime.tryParse(controller.text);
    final initial = parsed != null && parsed.year >= 1 && parsed.year <= 9999
        ? parsed
        : clock.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: '选择${label.replaceFirst('时间', '日期')}',
      confirmText: '下一步',
      cancelText: '取消',
    );
    if (!_valid || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: '选择$label',
      confirmText: '确定时间',
      cancelText: '取消',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (!_valid || time == null) return;
    String two(int value) => value.toString().padLeft(2, '0');
    final value =
        '${date.year.toString().padLeft(4, '0')}-${two(date.month)}-'
        '${two(date.day)} ${two(time.hour)}:${two(time.minute)}';
    controller.text = value;
    save(value);
  }
}
