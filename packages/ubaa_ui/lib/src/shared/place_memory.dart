import 'package:flutter/widgets.dart';

/// 空教室、图书馆等最后一次选择的校区、楼层、分区。
/// 只保存选项编号，作为下次进入时的默认值；空字符串表示“全部”。宿主可选择持久化。
class UiPlaceMemory extends InheritedWidget {
  const UiPlaceMemory({
    required this.values,
    required this.onChanged,
    required super.child,
  });
  final Map<String, String> values;
  final void Function(String key, String value) onChanged;

  static String? read(BuildContext context, String key) =>
      context.getInheritedWidgetOfExactType<UiPlaceMemory>()?.values[key];

  static void write(BuildContext context, String key, String? value) {
    final memory = context.getInheritedWidgetOfExactType<UiPlaceMemory>();
    if (memory == null || value == null) return;
    if (memory.values[key] == value) return;
    memory.onChanged(key, value);
  }

  @override
  bool updateShouldNotify(UiPlaceMemory oldWidget) => false;
}

/// 已登记的偏好键，宿主持久化时按此白名单保存。
abstract final class UiPlaceKeys {
  static const classroomCampus = 'classroom.campus';
  static const classroomBuilding = 'classroom.building';
  static const libbookLibrary = 'libbook.library';
  static const libbookStorey = 'libbook.storey';
  static const libbookArea = 'libbook.area';
  static const all = {
    classroomCampus,
    classroomBuilding,
    libbookLibrary,
    libbookStorey,
    libbookArea,
  };
}
