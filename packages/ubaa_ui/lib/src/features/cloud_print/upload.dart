part of 'view.dart';

class _UploadDialog extends StatefulWidget {
  const _UploadDialog({required this.files});
  final List<PrintSource> files;

  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  final _form = GlobalKey<FormState>();
  final _copies = TextEditingController(text: '1');
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController(text: '1');
  PrintPaper _paper = PrintPaper.original;
  PrintDuplex _duplex = PrintDuplex.single;
  bool _color = false;
  bool _range = false;

  bool get _canSetRange => widget.files.any(
    (file) =>
        !RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(file.name),
  );

  @override
  void dispose() {
    _copies.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  int? _number(TextEditingController field) => int.tryParse(field.text.trim());

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      PrintOptions(
        color: _color,
        paper: _paper,
        duplex: _duplex,
        copies: _number(_copies)!,
        from: _range ? _number(_from) : null,
        to: _range ? _number(_to) : null,
      ),
    );
  }

  Widget _field(
    TextEditingController field,
    String label,
    int limit, {
    bool end = false,
  }) => TextFormField(
    controller: field,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (_) {
      final value = _number(field);
      if (value == null || value < 1 || value > limit) {
        return field == _copies ? '请输入 1 至 999' : '请输入有效页码';
      }
      if (end && value < (_number(_from) ?? 1)) return '不能早于起始页';
      return null;
    },
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text('上传 ${widget.files.length} 份文件'),
    content: SizedBox(
      width: 420,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('上传后加入待打印队列，需到图书馆设备取件。本批文件使用相同设置。'),
            const SizedBox(height: 8),
            for (final file in widget.files)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(file.name),
              ),
            const Divider(height: 24),
            DropdownButtonFormField<PrintPaper>(
              initialValue: _paper,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '纸张'),
              items: const [
                DropdownMenuItem(
                  value: PrintPaper.original,
                  child: Text('原稿大小'),
                ),
                DropdownMenuItem(value: PrintPaper.a4, child: Text('A4')),
                DropdownMenuItem(value: PrintPaper.a3, child: Text('A3')),
              ],
              onChanged: (value) => setState(() => _paper = value!),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<PrintDuplex>(
              initialValue: _duplex,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '双面设置'),
              items: const [
                DropdownMenuItem(value: PrintDuplex.single, child: Text('单面')),
                DropdownMenuItem(
                  value: PrintDuplex.longEdge,
                  child: Text('双面 · 长边翻转'),
                ),
                DropdownMenuItem(
                  value: PrintDuplex.shortEdge,
                  child: Text('双面 · 短边翻转'),
                ),
              ],
              onChanged: (value) => setState(() => _duplex = value!),
            ),
            const SizedBox(height: 14),
            _field(_copies, '打印份数', 999),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('彩色打印'),
              value: _color,
              onChanged: (value) => setState(() => _color = value),
            ),
            if (_canSetRange)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('指定打印页码'),
                value: _range,
                onChanged: (value) => setState(() => _range = value),
              ),
            if (_range) ...[
              _field(_from, '起始页', 0xffffffff),
              const SizedBox(height: 14),
              _field(_to, '结束页', 0xffffffff, end: true),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('确认上传')),
    ],
  );
}
