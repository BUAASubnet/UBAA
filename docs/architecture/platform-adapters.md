# 本地平台适配清单

本页供维护 OHOS 平台插件的贡献者使用，汇总仓库内的本地插件适配、保留原因、验证入口和替换条件。这些适配存在的原因是上游尚未提供满足当前工具链的版本；固定来源、许可证和逐文件摘要见各包的 README、LICENSE 和 UPSTREAM.json。

| 包 | 保留原因 | 来源与本地差异 | 验证 |
|---|---|---|---|
| [flutter_secure_storage_ohos](../../packages/flutter_secure_storage_ohos/README.md) | OHOS HUKS 与标准 secure-storage interface | Csy_Gitee `f1a8ada0`、CPF `67c7b82e`；串行初始化、错误传播、认证密文与当前接口 | secure-storage-ohos.sh、ohos-check |
| [connectivity_plus_ohos](../../packages/connectivity_plus_ohos/README.md) | OHOS 网络变化，不处理学校会话 | CPF `9571de23`；标准列表、失败传播、订阅代次与解除 | platform-plugins-ohos.sh、ohos-check |
| [package_info_plus_ohos](../../packages/package_info_plus_ohos/README.md) | OHOS 标准包信息 | 同一 CPF 提交；当前 HAR 与 getAll 通道 | OHOS 分析、宿主测试与 HAP |

新增本地 fork 时：

- 登记用途、固定来源、许可证、最小差异、维护范围、验证入口与替换条件。
- 不复制过时的 Dart 门面，不降级官方平台依赖去迁就 fork。
- 业务规则继续归 Core、facade 和应用协调层。

替换条件：上游独立发布的版本同时满足当前工具链、平台 interface 和行为合同后，先通过现有的错误、生命周期、安全材料测试及平台构建，再替换本地包。构建与合成测试不能代替真实设备上的 HUKS、权限或订阅验证。
