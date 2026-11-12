import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/controller/state/activity.dart';

void main() {
  test('初始化中的认证有独立占用，外层结束后仍等待认证收尾', () {
    final owner = ControllerActivityOwner();
    final initialization = owner.begin(ControllerActivityKind.initialization);
    final authentication = owner.begin(ControllerActivityKind.authentication);
    initialization.finish();
    expect(owner.hasActive, isTrue);
    expect(owner.blocksHomeProjection, isTrue);
    expect(owner.blocksScheduledRead(recoveryRunsInReadLane: true), isTrue);
    authentication.finish();
    expect(owner.hasActive, isFalse);
    expect(owner.blocksHomeProjection, isFalse);
  });

  test('恢复允许本地投影与读取队列推进，重叠路线切换保持投影占用', () {
    final owner = ControllerActivityOwner();
    final recovery = owner.begin(ControllerActivityKind.recovery);
    expect(owner.hasActive, isTrue);
    expect(owner.onlyRecovery, isTrue);
    expect(owner.blocksHomeProjection, isFalse);
    expect(owner.blocksScheduledRead(recoveryRunsInReadLane: true), isFalse);
    expect(owner.blocksScheduledRead(recoveryRunsInReadLane: false), isTrue);

    final route = owner.begin(ControllerActivityKind.routeChange);
    expect(owner.onlyRecovery, isFalse);
    expect(owner.blocksHomeProjection, isTrue);
    recovery.finish();
    expect(owner.hasActive, isTrue);
    expect(owner.blocksScheduledRead(recoveryRunsInReadLane: true), isTrue);
    route.finish();
    expect(owner.hasActive, isFalse);
  });

  test('连续路线切换分别收尾，先完成的操作不能释放后开始的操作', () {
    final owner = ControllerActivityOwner();
    final first = owner.begin(ControllerActivityKind.routeChange);
    final second = owner.begin(ControllerActivityKind.routeChange);
    first.finish();
    expect(owner.hasActive, isTrue);
    expect(owner.blocksHomeProjection, isTrue);
    second.finish();
    expect(owner.hasActive, isFalse);
  });
}
