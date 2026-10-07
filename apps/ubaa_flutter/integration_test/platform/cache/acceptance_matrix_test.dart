import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../../../../../packages/ubaa_app/test/cache/startup_test.dart'
    as cached;
import '../../../../../packages/ubaa_app/test/recovery/required_test.dart'
    as scoped_recovery;
import '../../../../../packages/ubaa_app/test/recovery/resume_test.dart'
    as resume;
import '../../../../../packages/ubaa_app/test/cache/management/controller_test.dart'
    as management;
import '../../../../../packages/ubaa_app/test/cache/management/open_lifecycle_test.dart'
    as opening;
import '../../../../../packages/ubaa_app/test/features/judge/fallback/stability_test.dart'
    as partial;
import '../../../../../packages/ubaa_app/test/features/judge/online/scheduler_test.dart'
    as priority;
import '../../../../../packages/ubaa_app/test/features/grades/priority_test.dart'
    as grade_priority;
import '../../../../../packages/ubaa_app/test/features/grades/baseline_test.dart'
    as grade_baseline;
import '../../../../../packages/ubaa_app/test/write/cache/readback_test.dart'
    as readback;
import '../../../../../packages/ubaa_host/test/recovery/startup_test.dart'
    as startup;
import '../../../../../packages/ubaa_host/test/recovery/visible_resume_test.dart'
    as visible_resume;
import '../../../../../packages/ubaa_host/test/cache/local_clear_test.dart'
    as local_clear;
import '../../../../../packages/ubaa_host/test/write/cache_test.dart' as write;
import '../../../../../packages/ubaa_ui/test/features/home/cache_test.dart'
    as dates;
import '../../../../../packages/ubaa_ui/test/write/readback_test.dart' as hints;
import '../../../test/features/libbook/navigation_test.dart' as drafts;
import '../../synthetic/cache/bridge_test.dart' as ffi;
import '../network/recovery_test.dart' as network;
import '../credentials/material_test.dart' as native;

/// 原生容器中的脱敏异常矩阵；除独立临时缓存与安全材料外不读真实账号。
/// 学校协议/历史索引算法仍由 Core 确定性测试证明，不将此矩阵称为学校成功。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('原生缓存与安全材料', () {
    ffi.main();
    native.main();
  });
  group('缓存首页与原位恢复', () {
    cached.main();
    startup.main();
    scoped_recovery.main();
  });
  group('让位与部分结果', () {
    priority.main();
    grade_priority.main();
    partial.main();
  });
  group('生命周期与网络', () {
    visible_resume.main();
    resume.main();
    network.main();
    opening.main();
  });
  group('清理与写后核对', () {
    management.main();
    grade_baseline.main();
    local_clear.main();
    write.main();
    readback.main();
    hints.main();
  });
  group('日期与查询草稿', () {
    dates.main();
    drafts.main();
  });
}
