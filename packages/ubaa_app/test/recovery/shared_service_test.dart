import 'package:flutter_test/flutter_test.dart';
import '../runtime/session_recovery_probe.dart' as probe;

void main() {
  for (final entry in probe.cases.entries) {
    test(entry.key, entry.value);
  }
}
