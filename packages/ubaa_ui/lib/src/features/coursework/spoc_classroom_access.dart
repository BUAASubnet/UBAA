import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

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
  final Future<void> Function(Uri url) openExternal;
  final VideoPlaybackCapability? playback;
}
