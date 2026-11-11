# 现行代码与目录组织

本页供需要在代码中定位或新增模块的贡献者使用，列出各包的所有权、Dart 包内的目录结构、状态所有者和防止结构退化的约束。分层与请求流转先看[架构概览](overview.md)。决定依据是 [ADR 0006](../adr/0006-explicit-dart-modules.md)；旧目标树见[原设计快照](../archive/history/code-organization-2026-09-05.md)，整理过程见[实施记录](../archive/history/maintainability-implementation-2026-10-07.md)。

## 包边界

| 位置 | 所有权 |
|---|---|
| `crates/ubaa_core` | 协议、认证、路线、会话、缓存、解析和业务资格；宿主只使用 facade |
| `crates/ubaa_flutter_bridge` | typed FRB 映射、句柄和稳定合同 |
| `crates/ubaa_test_support` | 脱敏协议夹具与 Mock transport |
| `crates/ubaa_command` | 公共命令定义、参数、human/JSON 输出与退出码，供桌面命令模式经 Bridge 使用 |
| `tools/core_live` | 独立的只读真实验证程序 |
| `apps/ubaa_flutter`、`apps/ubaa_ohos` | 官方五平台与 OHOS 薄宿主、原生 runner；官方宿主同时提供桌面命令模式入口 |
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

AppController 是单一的 ChangeNotifier 实例。ControllerState 拥有共享生命周期与快照，具名 mixin 通过明确的状态/操作合同协作。内部成员以 `@internal` 限制在应用包内，宿主只使用公共方法和扩展；局部方法不重复登记进共享合同。

操作与状态提交按 [ADR 0007](../adr/0007-operation-scopes-and-verification.md) 进一步收窄：

- 认证完成 token 不依赖验证码状态。
- SessionScope/ReadScope 集中判断后端与代次是否有效。
- AcademicTermsOwner 独占学期缓存与在途合并，成绩通过 CurrentTermsReader 借用。
- ControllerReadCaches 提供统一的失效入口。

`@internal` 只约束包外访问，不能代替同包内的所有权划分。

Bridge 适配层的所有权：

- 领域函数借用 BridgeContext，不反向导入 BridgeBackend。
- 缓存句柄、账号、串行尾链和失效代次归 BridgeCacheState；交互挑战归 BridgeAuthenticationState。
- 不为单个领域另建账号会话或写状态机。

UI 模型与 callback 经构造参数传递。`part` 只用于同一局部 State 的紧密实现，不再聚合整个应用。公共 barrel 显式导出原组件，不批量公开内部实现。照片、锁码等专属生命周期独立管理。

## 测试与入口

普通测试按 `features/<领域>`、`session`、`recovery`、`cache`、`reads`、`write`、`contracts` 组织；共享夹具放 `test/support`。每个行为文件独立注册，不依赖其他文件留下的窗口、时钟或全局状态。

原生集成只保留真实平台能力和真实 FFI，其余合成全流程与人工预览已删除；合成夹具位于 `apps/ubaa_flutter/test/support/`，覆盖范围见[测试策略](../development/testing.md)。

## 防止退化

以下约束由 `just layout-check` 和 `just module-check` 检查，入口见[开发命令](../development/commands.md)：

- 受管手写源码每文件至多 1,000 行、每目录直属源码至多 16 个，包括 Python/CJS；FRB 生成文件与 Cargokit 排除在外。
- library 聚合规模、part 唯一归属和管理范围内的导入/导出环同时检查。UI library 上限 2,000 行，Bridge/Controller 上限 1,000 行，不能靠增加部件绕过。
- 依赖环按完整自有源码闭包验证，局部目录无环不等于整个包无环。当前规模以命令的实时结果为准。
- 原生入口与清单保持双向一致，辅助文件中的真实账号标记也要检查；真实和人工入口不进入默认 CI。
- 公开 API 编译、类型、内部成员边界、行为、golden 与 FRB 生成一致性各自保留独立覆盖。

阈值只是防线，代码定位和状态所有权仍需评审。小领域保持平铺；机械移动、行为修改、生成输出和 golden 更新分开审查。

## 文档与证据

各类文档的存放位置见[文档规范](../development/conventions.md#文档规范)。历史验收媒体在仓库外，元数据按[批次索引](../design/evidence/batches.md)定位。默认源码检索使用 `just source-files` 或限定源码目录的 `rg`。
