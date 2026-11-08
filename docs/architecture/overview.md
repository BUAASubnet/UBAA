# 架构概览

## 当前实现

Rust Core 负责协议、认证、路线、Cookie、会话、加密、解析、缓存与业务资格。CLI 和 FRB 生产调用只经 facade；Dart 与平台宿主不读取 upstream 内部状态，不拼接学校 URL 或处理原始响应。

```mermaid
flowchart TD
  CLI[CLI 参数与输出] --> F[Core facade]
  Host[Flutter 与 OHOS 薄宿主] --> H[共享 Host 接线]
  H --> A[AppController 单一状态实例]
  H --> U[独立 UI 领域组件]
  H --> P[平台 typed 能力]
  A --> W[唯一 WriteCoordinator]
  A --> B[BridgeBackend 与领域适配]
  B --> C[BridgeContext 客户端及账号状态]
  B --> R[typed FRB]
  R --> F
  F --> Core[认证 业务 缓存 路线与会话]
  Core --> T[私有 transport 与上游解析]
```

UbaaClient 是普通聚合 facade。Direct/WebVPN runtime、配置 revision、网关探测和双路线协调在 Core 内；RouteClient 仅用于明确固定路线的诊断/测试。原始 HTTP transport 不自动跟随重定向，不拥有全局 Cookie，跳转规则由已验证业务协议决定。

CLI JSON schema v14 独立于磁盘 Session v2、配置 v1、缓存 schema v8。CLI envelope 的 schema v14 由序列化和 JSON Schema 合同共同验证，schema-v14 聚合输出覆盖成功、业务失败与参数错误。Flutter bridge contract v56 由 Rust 常量、Dart 接受版本与 codegen 零漂移检查共同约束。

AppController 的局部实现通过显式状态/操作合同协作，保持同一 ChangeNotifier 实例、账号代次和快照。BridgeContext 持有同一客户端，账号缓存与交互认证各有唯一状态对象。UI 消费不可变模型与回调；公开组件由显式 barrel 导出，局部 State 不越过组件边界供测试直接修改。详细路径见[现行代码组织](code-organization.md)。

写入资格与目标由 Core 的新鲜读取签发。App 的 WriteCoordinator 唯一拥有意图、准备、确认、取消、提交、失效与回读状态；宿主只注入能力，UI 不从中文文案或展示字段推断资格。非幂等最终提交至多一次，unknown 禁止自动重试；回读固定原路线且不能把未知结果升级为成功。完整问卷、Cookie、Token、验证码等材料不越过各自专属边界。

系统安全材料与加密缓存保留明确错误，不降级明文。业务协议与本地平台插件分别治理，本地 fork 的来源和退出条件见[适配清单](platform-adapters.md)。

实现、确定性测试、原生合成、Core-live、真实 App、设备和正式发布是独立证据。当前范围见 [goal.md](../../goal.md)，实际结果见[状态页](../migration/status.md)；历史说明见[归档](../migration/history/architecture-before-maintainability-2026-10-07.md)。

## 目标入口与职责

App 命令模式采用[共享设计](../design/desktop-shared-state.md)。GUI 和命令复用服务实现，每个进程持有自己的客户端与资源，通过共同资料空间和持久状态协调账号及数据。

```mermaid
flowchart TD
  GUI[Flutter / OHOS 界面] --> Host[宿主接线]
  CMD[桌面命令入口] --> Commands[公共命令定义与输出]
  Host --> App[无界面应用服务]
  Commands --> App
  App --> Bridge[typed Bridge / FRB]
  Bridge --> Facade[Core facade]
  Facade --> Core[协议、业务、会话、缓存与日程存储]
  Host --> Platform[安全材料、目录与文件能力]
  App --> Platform
```

| 所有者 | 责任 |
|---|---|
| Core | 协议与业务规则、Direct/WebVPN 会话、持久化、账号访问校验和实际发送边界 |
| Bridge | 稳定类型及 Core 句柄投影，创建、替换和关闭时保持账号绑定与控制句柄一致 |
| 应用服务 | 账号选择、会话恢复、日程操作和用例编排，GUI 与命令复用相同规则 |
| Host / Platform | 入口、生命周期接线、安全存储、路径和文件选择/保存 |
| UI / 命令展示 | 用户输入、状态和结果呈现，消费服务能力 |

客户端、账号绑定、取消和关闭控制由其现有资源所有者统一更新。Core 更换时必须同时处理关联状态；避免由多个互不知情的对象各自维护一份当前客户端。具体改动针对已知缺陷实施，不要求新增协调层或重组现有包。

## 日程交付边界

日程界面调用已有独立日程服务，复用 Core 的重复展开、学校投影、本地覆盖和范围导出。学校事项的本地完成、隐藏和备注只修改日程存储，学校业务写入仍经过原 WriteCoordinator 和 Core 资格检查。

共享命令候选的跨进程能力不构成日程 GUI 的前置条件。日程工作可从主线已有服务开始；引入候选实现时再处理相关阻塞和整合验证。平台、协议和账号隔离规则继续遵循现有合同。
