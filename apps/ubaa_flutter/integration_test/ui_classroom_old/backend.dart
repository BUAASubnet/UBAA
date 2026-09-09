import 'dart:async';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../ui_academic_old/backend.dart';

/// 明确合成空教室响应；复用原学业离线宿主，禁止学校写入。
class ClassroomOldBackend extends AcademicOldBackend {
  ClassroomOldBackend({super.state});
  final classroomReads = <FeatureQuery>[];
  bool fail = false, empty = false;
  Completer<void>? classroomPending;
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (feature != FeatureId.classroom) {
      return super.loadFeatureQuery(feature, query);
    }
    classroomReads.add(query);
    if (classroomPending case final gate?) await gate.future;
    if (fail || (state == 'first-error' && classroomReads.length == 1)) {
      throw const BackendException(UbaaErrorCode.networkError);
    }
    if (empty || state == 'empty') {
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    final date = query.date ?? DateTime(2026, 9, 9);
    final day =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final details = <FeatureDetail>[];
    final count = state == 'many' ? 42 : 5;
    for (var i = 0; i < count; i++) {
      final floor = i % 2 == 0 ? 'F1' : 'F2';
      final sections = switch (i % 5) {
        0 => '1,3,13',
        1 => '2,4,14',
        2 => '',
        3 => '未开放',
        _ => '03,14,15',
      };
      if (query.floorId?.isNotEmpty == true && query.floorId != floor) continue;
      if (query.section?.isNotEmpty == true &&
          !sections.split(',').contains(query.section)) {
        continue;
      }
      details.add(
        FeatureDetail(
          title: title('合成教室${i + 1}'),
          fields: const [FeatureField(label: '原字段', value: '脱敏保留值')],
          presentation: ClassroomPresentation(
            roomId: 'ROOM-SAFE-${i + 1}',
            floorId: floor,
            floorName: title(i % 2 == 0 ? '合成一号楼' : '合成二号楼'),
            availableSections: sections,
            queryDate: day,
            campus: query.campus ?? 1,
          ),
        ),
      );
    }
    return details.isEmpty
        ? const FeatureResult.empty(resolvedRoute: ConnectionMode.direct)
        : FeatureResult.success(
            details: details,
            resolvedRoute: ConnectionMode.direct,
          );
  }
}
