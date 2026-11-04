import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/mapping.dart' show bridgeToConnectionMode;

DateTime? _time(int? value) => value == null
    ? null
    : DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
BhpanItem bhpanItem(BridgeBhpanItem i) => BhpanItem(
  handle: i.handle,
  name: i.name,
  kind: BhpanItemKind.values[i.kind.index],
  scope: BhpanScope.values[i.scope.index],
  bytes: i.bytes?.toInt(),
  createdAt: _time(i.createdAt),
  modifiedAt: _time(i.modifiedAt),
);
BhpanPage bhpanPage(BridgeBhpanPage p) => BhpanPage(
  items: List.unmodifiable(p.items.map(bhpanItem)),
  range: BhpanListRange.values[p.range.index],
  route: bridgeToConnectionMode(p.route),
  fetchedAt: _time(p.fetchedAt)!,
);
BhpanShare bhpanShare(BridgeBhpanShare s) => BhpanShare(
  handle: s.handle,
  title: s.title,
  expiresAt: s.expiresAt,
  passwordRequired: s.passwordRequired,
  limitedTimes: s.limitedTimes.toInt(),
  permissions: List.unmodifiable(
    s.permissions.map((p) => BhpanPermission.values[p.index]),
  ),
  canUpdate: s.canUpdate,
);
