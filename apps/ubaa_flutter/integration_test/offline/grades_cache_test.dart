import 'package:integration_test/integration_test.dart';
import '../../../../packages/ubaa_host/test/offline/grades_test.dart' as host;
import '../../../../packages/ubaa_ui/test/academic/grades_old_test.dart' as ui;

// 所有输入为合成账号和成绩；不调用学校网络或读取真实安全材料。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  host.main();
  ui.main();
}
