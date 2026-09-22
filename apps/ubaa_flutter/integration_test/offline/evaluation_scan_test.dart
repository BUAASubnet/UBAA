import 'package:integration_test/integration_test.dart';
import '../../../../packages/ubaa_app/test/offline/evaluation/scheduler_test.dart'
    as scheduler;
import 'cache_bridge_test.dart' as ffi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ffi.main();
  scheduler.main();
}
