import 'academic_terms.dart';
import 'models.dart';

/// 内存读取缓存的生命周期所有者；清理与后端重建只调用同一失效入口。
/// 快照是否保留 stale 仍由调用方决定，本类不改变可见页面。
final class ControllerReadCaches {
  final terms = AcademicTermsOwner();
  HomeSupplementCache? home;
  GradesReadCache? grades;
  AcademicWeeksCache? weeks;
  CgyyPurposeCache? purposes;

  void invalidate() {
    terms.invalidate();
    home = null;
    grades = null;
    weeks = null;
    purposes = null;
  }
}
