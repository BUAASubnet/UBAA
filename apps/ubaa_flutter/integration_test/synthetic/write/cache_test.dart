import 'package:integration_test/integration_test.dart';
import '../../../../../packages/ubaa_host/test/write/cache_test.dart' as host;
import '../cache/bridge_test.dart' as ffi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ffi.main();
  host.main();
}
