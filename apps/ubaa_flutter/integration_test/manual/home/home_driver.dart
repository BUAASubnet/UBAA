import '../../synthetic/home/flow_test.dart' as scenario;

/// 显式人工巡检入口，不注册自动回归用例。
Future<void> main() => scenario.runInspection();
