part of '../widgets.dart';

class _YgdkFormDialog extends StatefulWidget {
  const _YgdkFormDialog({
    required this.action,
    required this.title,
    required this.onPickPhoto,
  });

  final YgdkSubmitAction action;
  final String title;
  final YgdkPhotoPicker? onPickPhoto;

  @override
  State<_YgdkFormDialog> createState() => _YgdkFormDialogState();
}

class _YgdkFormDialogState extends State<_YgdkFormDialog> {
  static const _previewCacheWidth = 720;
  static const _previewCacheHeight = 480;

  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _placeController;
  YgdkPhotoInput? _photo;
  Uint8List? _previewBytes;
  String? _error;
  bool _picking = false;
  bool _shareToSquare = false;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController();
    _endController = TextEditingController();
    _placeController = TextEditingController(text: '操场');
  }

  @override
  void dispose() {
    _releasePhotoReferences();
    _startController.dispose();
    _endController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('填写阳光打卡信息'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '项目：${widget.title}'
                '（分类 ${widget.action.classifyId} / '
                '项目 ${widget.action.itemId}）',
              ),
            ),
            TextField(
              controller: _startController,
              decoration: const InputDecoration(
                labelText: '开始时间',
                hintText: 'YYYY-MM-DD HH:mm',
              ),
            ),
            TextField(
              controller: _endController,
              decoration: const InputDecoration(
                labelText: '结束时间',
                hintText: 'YYYY-MM-DD HH:mm',
              ),
            ),
            TextField(
              controller: _placeController,
              decoration: const InputDecoration(labelText: '打卡地点'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
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
            if (_previewBytes case final bytes?) ...<Widget>[
              const SizedBox(height: 8),
              ClipRRect(
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
                    child: Center(child: Text('照片预览不可用，请重新选择。')),
                  ),
                ),
              ),
            ],
            if (widget.onPickPhoto == null)
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('当前运行环境未提供照片选择器，无法提交打卡。'),
              ),
            CheckboxListTile(
              value: _shareToSquare,
              onChanged: (value) => setState(() {
                _shareToSquare = value ?? false;
              }),
              contentPadding: EdgeInsets.zero,
              title: const Text('分享到打卡广场'),
            ),
            if (_error case final message?)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: <Widget>[
      TextButton(onPressed: _cancel, child: const Text('取消')),
      FilledButton(onPressed: _continue, child: const Text('继续确认')),
    ],
  );

  Future<void> _pickPhoto() async {
    final picker = widget.onPickPhoto;
    if (picker == null || _picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked = await picker();
      if (!mounted) return;
      setState(() {
        _releasePhotoReferences();
        _photo = picked;
        _previewBytes = picked == null
            ? null
            : Uint8List.fromList(picked.bytes);
        _error = picked == null ? '未选择照片，阳光打卡必须附带照片。' : null;
      });
    } on Object {
      if (mounted) {
        setState(() => _error = '照片选择失败，请检查平台权限后重试。');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _continue() {
    final start = _startController.text;
    final end = _endController.text;
    final photo = _photo;
    if (start.trim().isEmpty || end.trim().isEmpty || photo == null) {
      setState(() => _error = '请填写完整时间并选择照片。');
      return;
    }
    final input = YgdkSubmitInput(
      action: widget.action,
      startTime: start,
      endTime: end,
      place: _placeController.text.trim(),
      shareToSquare: _shareToSquare,
      photo: photo,
    );
    _releasePhotoReferences();
    Navigator.of(context).pop(input);
  }

  void _cancel() {
    _releasePhotoReferences();
    Navigator.of(context).pop();
  }

  void _releasePhotoReferences() {
    final bytes = _previewBytes;
    if (bytes != null) {
      unawaited(
        ResizeImage(
          MemoryImage(bytes),
          width: _previewCacheWidth,
          height: _previewCacheHeight,
        ).evict(cache: PaintingBinding.instance.imageCache),
      );
    }
    _previewBytes = null;
    _photo = null;
  }
}

extension _YgdkWriteForm on _FeatureDetailListState {
  Future<void> _showYgdkForm(
    BuildContext context, {
    required YgdkSubmitAction action,
    required String title,
  }) async {
    final input = await showDialog<YgdkSubmitInput>(
      context: context,
      builder: (_) => _YgdkFormDialog(
        action: action,
        title: title,
        onPickPhoto: widget.onPickYgdkPhoto,
      ),
    );
    if (input != null && mounted) {
      await widget.onYgdkSubmitWrite?.call(input);
    }
  }
}
