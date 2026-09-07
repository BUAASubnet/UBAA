/// 仅含已公开业务 DTO 的展示投影，不承载写入资格或上游材料。
library;

part 'presentation/schedule.dart';
part 'presentation/exam.dart';
part 'presentation/grade.dart';
part 'presentation/classroom.dart';

sealed class FeaturePresentation {
  const FeaturePresentation();
}
