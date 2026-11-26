import 'package:ubaa_domain/ubaa_domain.dart';

/// 课堂功能由宿主提供的能力。用 [courses] 的课程标识打开目录，不按课程名查找。
final class SpocClassroomAccess {
  const SpocClassroomAccess({
    required this.service,
    required this.courses,
    required this.openExternal,
    this.playback,
  });

  final ClassroomService service;
  final Future<SpocRead<List<SpocCourse>>> Function() courses;
  final Future<bool> Function(Uri url) openExternal;

  /// 平台播放能力接入前为空。
  final Object? playback;
}
