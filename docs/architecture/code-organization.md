# 现行代码与目录组织

历史尺寸、旧目标树与实施流水见[原设计快照](../migration/history/code-organization-2026-09-05.md)。现行决定是 [ADR 0006](../adr/0006-explicit-dart-modules.md)，验证见[整理记录](../migration/maintainability-implementation-2026-10-07.md)。

## 包边界

| 位置 | 所有权 |
|---|---|
| `crates/ubaa-core` | 协议、认证、路线、会话、缓存、解析和业务资格；宿主只使用 facade |
| `crates/ubaa-flutter-bridge` | typed FRB 映射、句柄和稳定合同 |
| `crates/ubaa-test-support` | 脱敏协议夹具与 Mock transport |
| `apps/ubaa-cli` | CLI 参数、human/JSON、退出码和只读诊断 |
| `apps/ubaa_flutter`、`apps/ubaa_ohos` | 官方五端与 OHOS 薄宿主、原生 runner |
| `packages/ubaa_domain` | 不可变展示、查询和写状态模型 |
| `packages/ubaa_app` | 会话与用例协调、Bridge 适配、唯一写入状态机 |
| `packages/ubaa_host` | AppController 生命周期与平台/UI callback 接线 |
| `packages/ubaa_platform` | 平台能力、安全材料、目录、偏好和类型化错误 |
| `packages/ubaa_ui` | 领域组件、导航、查询、表单与响应式展示 |
| `packages/ubaa_bindings` | FRB 生成输出与锁定 Cargokit，不手改生成实现 |
| 三个 OHOS 插件包 | 上游原生适配和最小本地修订，见[适配清单](platform-adapters.md) |

Rust package 保留 `ubaa-core`，Dart package 保留 `ubaa_app`。领域名称沿用 `schedule/grades/bykc/cgyy/libbook/ygdk/spoc/judge/evaluation/signin`，不继续增加 `boya/rooms/sports` 等目录别名。

## 模块与状态

```text
ubaa_app/lib/src/
  controller/
    app_controller.dart       # 单一实例、局部实现组合与公共兼容入口
    state/                    # 状态所有者、记录类型、跨模块操作合同
    session/ recovery/ cache/ # 横切生命周期
    reads/ write/             # 调度与写回读
    features/<领域>/          # 领域协调
  bridge/
    bridge_backend.dart       # 公共后端能力组合
    context.dart              # 同一客户端、账号缓存与交互认证状态
    auth/ cache/              # 会话和句柄生命周期
    features/<领域>/          # reader、cache、projection
    read/ write/ home/        # 跨领域分派与聚合
    support/                  # 共用映射
  write/                      # 唯一 WriteCoordinator 和收据核对

ubaa_ui/lib/src/
  widgets.dart                # 原公开组件的显式导出
  app/                        # 壳、登录、个人页和设置
  features/<领域>/            # 独立领域组件
  common/query/               # 查询面板自己的 State 和字段部件
  common/details/             # 详情列表自己的 State 和动作接线
  shared/                     # 无业务状态的共用展示
  write/<领域>/               # 表单、草稿与局部状态
```

AppController 仍是一个 ChangeNotifier 实例。ControllerState 拥有共享生命周期与快照，具名 mixin 通过明确的状态/操作合同协作。内部成员以 `@internal` 限制在应用包内，宿主只使用公共方法和扩展；局部方法不重复登记进共享合同。

Bridge 领域函数借用 BridgeContext，不能反向导入 BridgeBackend。缓存句柄、账号、串行尾链和失效代次归 BridgeCacheState；交互挑战归 BridgeAuthenticationState。不得为单个领域另建账号会话或写状态机。

UI 模型与 callback 经构造参数传递。`part` 只用于同一局部 State 的紧密实现，不再聚合整个应用。公共 barrel 显式导出原组件，不批量公开内部实现。照片、锁码等专属生命周期独立管理。

## 测试与入口

普通测试按 `features/<领域>`、`session`、`recovery`、`cache`、`reads`、`write`、`contracts` 组织；共享夹具放 `test/support`。每个行为文件独立注册，不依赖其他文件留下的窗口、时钟或全局状态。

原生入口按 `integration_test/synthetic`、`platform`、`live`、`manual` 分类。人工巡检通过独立 `*_driver.dart`，不再用开关把自动测试入口变成常驻 App。入口、平台、环境条件与 CI 归属集中于 `scripts/integration-tests.json`，以 `just integration-list` 查询。

## 防止退化

- `just layout-check`：受管手写源码每文件至多 1,000 行、每目录直属源码至多 16 个，包含 Python/CJS；FRB 与 Cargokit 排除规则保持。
- `just module-check`：library 聚合规模、part 唯一归属和管理范围内导入/导出环。UI 上限 2,000 行，Bridge/Controller 上限 1,000 行，不允许靠增加部件绕过。
- 当前基线：UI 63 个 library、最大 1,960 行；Bridge 45 个、最大 653 行；Controller（含既有辅助组件）46 个、最大 731 行，均无环。
- `just integration-check`：实际入口与清单双向一致，递归检查辅助文件中的真实账号标记；真实和人工入口不得进入默认 CI。
- `just flutter-check`：公开 API 编译、类型、内部成员边界、行为与 golden；FRB 零漂移由 `just flutter-codegen-check` 独立验证。

阈值是防线，代码定位和状态所有权仍需评审。小领域保持平铺；机械移动、行为修改、生成输出和 golden 更新分别审查。认证/读取行为变化继续先做双来源对照和 RED→GREEN。

## 文档与证据

`goal.md` 是当前合同，`migration/status.md` 是最新状态；`architecture/`、`development/` 只承载现行规范和操作。历史流水进入 `migration/history`，新决策进入 `adr`。历史验收媒体在仓库外，元数据按[批次索引](../design/evidence/batches.md)定位；默认源码检索使用 `just source-files` 或限定源码目录的 `rg`。
