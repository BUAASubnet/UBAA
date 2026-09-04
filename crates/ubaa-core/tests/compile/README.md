# Facade 测试注入编译夹具

两个独立 Cargo 夹具编译完全相同的调用源码，且源码不使用 `cfg`：

- `facade_testing_feature_off` 不启用 Core feature，必须编译失败；失败点是
  `facade::testing` 与五个注入构造器不可访问。
- `facade_testing_feature_on` 只启用 `test-contract`，必须编译成功；它从
  `facade::testing` 导入构造参数与端口类型，并调用现有的
  `RouteClient::with_transport`、`RouteClient::with_transport_at`、
  `UbaaClient::with_transports`、`UbaaClient::with_routing` 和测试专用的
  `UbaaClient::with_routing_and_probe_ttl`。

夹具自成空 workspace，避免调用方 workspace 的 feature 合并把关闭态误变成开启态。
正式门禁应分别检查“关闭态失败、开启态成功”，不得用 crate 级 `cfg` 把任一夹具静默变成零测试。
