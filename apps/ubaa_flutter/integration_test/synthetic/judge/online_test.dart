import 'package:integration_test/integration_test.dart';
import '../../../../../packages/ubaa_app/test/features/judge/online/bridge_test.dart'
    as projection;
import '../../../../../packages/ubaa_app/test/features/judge/online/scheduler_test.dart'
    as scheduler;
import '../cache/bridge_test.dart' as ffi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ffi.main();
  projection.main();
  scheduler.main();
}
