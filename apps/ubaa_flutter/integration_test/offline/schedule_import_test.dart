import 'package:integration_test/integration_test.dart';
import '../../../../packages/ubaa_host/test/offline/schedule_import_test.dart'
    as host;
import '../../../../packages/ubaa_ui/test/academic/schedule_import_test.dart'
    as ui;

// 合成学期及可控只读任务；不使用真实账号或学校网络。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  host.main();
  ui.main();
}
