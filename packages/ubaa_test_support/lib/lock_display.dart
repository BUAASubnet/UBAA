import 'dart:async';

import 'package:ubaa_app/ubaa_app.dart';
import 'demo_backend.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class SyntheticLockSession implements CgyyLockDisplaySession {
  final events = StreamController<void>.broadcast(sync: true);
  final reads = <Completer<CgyyLockDisplay>>[];
  bool closed = false;
  @override
  Stream<void> get cancelled => events.stream;
  @override
  Future<CgyyLockDisplay> read() {
    final c = Completer<CgyyLockDisplay>();
    reads.add(c);
    return c.future;
  }

  @override
  void cancel() {
    if (closed) return;
    closed = true;
    events.add(null);
    unawaited(events.close());
  }
}

class SyntheticLockBackend extends DemoBackend
    implements CgyyLockDisplayBackend, FeatureQueryBackend {
  final sessions = <SyntheticLockSession>[];
  Completer<CgyyLockDisplaySession>? opening;
  int ordinaryLockReads = 0;
  @override
  Future<AuthStatus> authStatus() async => AuthStatus.signedIn;
  @override
  Future<UserSummary?> userInfo() async =>
      const UserSummary(username: 'synthetic-account');
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async =>
      FeatureResult.empty();
  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.cgyyLockCode) ordinaryLockReads++;
    return FeatureResult.empty();
  }

  @override
  Future<CgyyLockDisplaySession> openLockDisplay() async {
    if (opening case final gate?) return gate.future;
    final session = SyntheticLockSession();
    sessions.add(session);
    return session;
  }
}
