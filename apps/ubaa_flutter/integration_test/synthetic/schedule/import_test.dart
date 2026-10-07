import 'package:integration_test/integration_test.dart';
import '../../../../../packages/ubaa_ui/test/features/schedule/offline_test.dart'
    as offline_ui;
import '../../../../../packages/ubaa_host/test/features/schedule/import_test.dart'
    as host;
import '../../../../../packages/ubaa_ui/test/features/schedule/import_test.dart'
    as ui;

// 合成学期及可控只读任务；不使用真实账号或学校网络。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  host.main();
  ui.main();
  offline_ui.main();
}
