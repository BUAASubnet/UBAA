part of '../widgets.dart';

extension _YgdkFormTime on _YgdkFormPageState {
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
