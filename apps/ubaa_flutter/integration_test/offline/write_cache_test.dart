import 'package:integration_test/integration_test.dart';
import '../../../../packages/ubaa_host/test/offline/write_cache_test.dart'
    as host;
import 'cache_bridge_test.dart' as ffi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ffi.main();
  host.main();
}
