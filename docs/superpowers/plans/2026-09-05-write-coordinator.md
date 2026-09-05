# Phase 11K 唯一写入协调器实施计划

> **执行要求：** 使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans` 按任务实施；用复选框记录实际完成情况。父计划已授权继续执行，本文件不新增审批阶段。

**目标：** 让生产 Flutter 写入只有一个状态机，保留现有 typed 输入、一次性确认、错误、安全回读、宿主能力和 UI 行为。

**架构：** `ubaa_domain` 定义 immutable `WriteState`/`WriteOutcome`；`ubaa_app` 实现并持有唯一 `WriteCoordinator`；`ubaa_host` 向 UI 注入状态和命令。`WriteFlowController` 是同一实现的兼容类型别名，UI 不直接依赖 app 或 bindings。

**技术：** Dart 3.11.5、Flutter 3.41.9、ChangeNotifier、现有 Flutter widget/golden/host 测试与固定 FRB 生成门禁。

**设计依据：** [代码组织设计](../../architecture/code-organization.md) 第 6.2 节；[父实施计划](2026-09-03-code-organization.md) Phase 11K；[当前状态](../../migration/status.md)。执行时先读取 Phase 11J 收口后的代码，不能把本文件的审查行数当作固定切割位置。

**状态：** 2026-09-05，已提交 `b6ff2c7`；domain/app/Host/UI 已完成，完整 Rust、Flutter 374 项、FRB 零漂移、macOS integration 7 项、本机三平台产物、OHOS API26 无签名 HAP 和独立复审通过。

## 1. 全局约束

- 冻结来源、凭据、运行会话、验证码和真实响应只读；本阶段不执行真实写入。
- 依赖方向为 `hosts -> ubaa_host -> ubaa_app + ubaa_ui + ubaa_platform`、`ubaa_app -> bindings + domain + platform`、`ubaa_ui -> domain`。
- `ubaa_domain` 保持纯 Dart，仅依赖现有 `meta`；不把 Flutter `Listenable`、app 异常或 backend 接口引入 domain。
- 不新增 package、根 Pub workspace、通用 service locator 或跨领域写接口；使用现有 callback 注入方式。
- UI 不保存 pending intent、提交标志、取消标志、收据或最后写结果；tab、查询、筛选和表单输入仍属于 UI。
- Core/bridge 仍是最终资格、intent 原子消费和单次网络发送的权威。本阶段不重新解释协议或改变 FRB/CLI schema。
- 旧公开 `WriteFlowController`、`WriteCommitter`、`WritePreparer`、`WriteDiscarder` 名字、导入路径及旧方法返回类型保持可用。
- golden 的路径、字节、SHA-256 不变，不运行 `--update-goldens`；原有测试名称、注册顺序与断言必须保留。
- Phase 11K 的行为收口与 Phase 12 的 UI 物理拆分分别提交；前者不顺手搬迁整个 UI。
- 每个提交前按父计划运行 refs、layout、敏感扫描、focused、完整 Rust/Flutter/FRB 门禁并审查精确暂存文件。

## 2. 当前事实和要关闭的差异

审查时 `packages/ubaa_ui/lib/src/widgets.dart` 为 4118 行。`_UbaaMainShellState` 保存 `_pendingWrite`、`_writeError`、`_writeSubmitting`、`_writeDiscarding`，同时实现 prepare、cancel、confirm、领域回读、收据核对与消息投影。`packages/ubaa_app/lib/src/write_controller.dart` 为 149 行，已有 `WriteFlowController` 及独立测试，但生产 Host/UI 没有使用它。

旧控制器测试固定 `confirm() -> Future<WriteCommitResult?>`，并要求 `BackendException` 继续以原类型向旧调用者抛出。旧 `confirm` 的未知异常没有覆盖消费后的清理；UI 当前另有通用异常处理。因此不能仅把四个字段搬到 app 后宣称两条路径等价，必须先补 RED 再收口未知异常和生命周期晚到结果。

Host 的 `AppController` 已负责 backend 重建、路线切换、登录、注销和 dispose，并有 `_lifecycleEpoch`。写入失效应接入这些现有边界，不用 UI 是否 mounted 代替会话生命周期。

## 3. 文件所有权

| 路径 | 职责 |
|---|---|
| `packages/ubaa_domain/lib/src/write/state.dart` | 新增 phase、immutable state、一次性返回的安全完成结果 |
| `packages/ubaa_domain/lib/src/models.dart` | 稳定导出新 domain 类型，不放实现 |
| `packages/ubaa_app/lib/src/write/coordinator.dart` | 唯一状态机、代次、异步操作所有权、旧和安全调用入口 |
| `packages/ubaa_app/lib/src/write/receipt_verifier.dart` | 原 UI 回读条件、调用顺序、安全核对标志和最终消息；不拥有 pending 状态 |
| `packages/ubaa_app/lib/src/write_controller.dart` | 兼容导出和 `WriteFlowController` 类型别名 |
| `packages/ubaa_app/lib/src/controller/app_controller.dart` | 持有当前 backend 的 coordinator、转发通知、执行失效与替换 |
| `packages/ubaa_app/lib/src/controller/app_controller/write_lifecycle.dart` | 固定 backend 的构造和 commit/discard 校验 helper |
| `packages/ubaa_host/lib/src/callbacks.dart` | 注入状态、三个安全命令及既有领域 prepare；平台照片/位置能力仍在 host |
| `packages/ubaa_ui/lib/src/write_callbacks.dart` | 三个 UI 命令 typedef；继续保留既有公开领域 callback 名字 |
| `packages/ubaa_ui/lib/src/widgets.dart` | 仅消费 state、转发命令并显示 outcome.message；删除第二套状态、回读及消息决策实现 |
| `packages/ubaa_app/test/write_controller_test.dart` | 保留旧公共行为合同，作为兼容入口 |
| `packages/ubaa_app/test/write_coordinator_test.dart` | 新增实际状态机、失效和回读测试根入口 |
| `packages/ubaa_app/test/write_coordinator/` | `flow.dart`、`invalidation.dart`、`readback.dart`，按行为注册原子测试；最小共享构造保留在测试根入口 |
| `packages/ubaa_app/test/write_coordinator_dispose_test.dart` | 取消、提交、回读等待期间销毁后的成功/失败晚到结果 |
| `packages/ubaa_app/test/app_write_lifecycle_test.dart` | AppController 对单一协调器、旧 backend 和回读的生命周期边界 |
| `packages/ubaa_ui/test/support/write_harness.dart` | 新增仅供测试的真实 coordinator 生命周期及 callback 接线 |
| `packages/ubaa_ui/test/widgets/` | 原测试按必要的构造点迁移，保留行为断言和注册顺序 |
| `packages/ubaa_host/test/ubaa_app_host/` | 证明生产 Host 确实使用 coordinator，覆盖生命周期与能力变化 |

`state.dart` 放在 domain 是对父计划目标路径的明确细化；不另建仅为路径好看的 app `state.dart`。新增导出应显式登记公共 API 合同，不改旧类型身份。

## 4. 具体接口

### 4.1 Domain 状态和完成结果

```dart
enum WritePhase {
  idle,
  preparing,
  ready,
  cancelling,
  committing,
  readingBack,
  invalidating,
}

@immutable
class WriteState {
  const WriteState.idle()
    : phase = WritePhase.idle, intent = null, error = null;

  const WriteState({required this.phase, this.intent, this.error});

  final WritePhase phase;
  final WriteIntent? intent;
  final UiError? error;

  bool get isSubmitting => switch (phase) {
    WritePhase.preparing || WritePhase.cancelling || WritePhase.committing ||
    WritePhase.readingBack || WritePhase.invalidating => true,
    WritePhase.idle || WritePhase.ready => false,
  };
  bool get isDiscarding => phase == WritePhase.cancelling;
}

@immutable
class WriteOutcome {
  const WriteOutcome({
    required this.operation,
    required this.message,
    this.result,
    this.error,
    this.cgyyReceiptVerified,
    this.cgyyCancellationVerified,
    this.ygdkReadbackAttempted = false,
  }) : assert((result == null) != (error == null));

  final WriteOperation operation;
  final String message;
  final WriteCommitResult? result;
  final UiError? error;
  final bool? cgyyReceiptVerified;
  final bool? cgyyCancellationVerified;
  final bool ygdkReadbackAttempted;
}
```

`WriteOutcome` 不存到 `WriteState`；一次 confirm future 只返回一次终态，避免 AppController 的其它通知反复显示 SnackBar。结果与错误必须恰有一个；message 在 app 按原有规则生成，UI 只显示它。所有收据仍消费现有安全 domain DTO，不加入 raw payload、原异常、堆栈或未经白名单投影的上游消息。

`ready/cancelling/committing/readingBack` 可以携带同一 intent 供确认页展示；提交开始后该 intent 仅是展示快照，phase 门禁不再允许消费。`idle/preparing/invalidating` 不携带 intent。生产实现每次发布新 immutable state，不分别维护四个可变布尔值。

### 4.2 App 唯一实现与兼容入口

```dart
typedef WriteCommitter = Future<WriteCommitResult> Function(String intentId);
typedef WritePreparer = Future<WriteIntent> Function();
typedef WriteDiscarder = Future<void> Function(String intentId);

class WriteCoordinator extends ChangeNotifier {
  WriteCoordinator({
    required WriteCommitter commit,
    WriteDiscarder? discard,
    WriteReceiptVerifier? receiptVerifier,
    DateTime Function()? now,
    bool Function()? canStart,
  });

  WriteState get state;
  WriteIntent? get intent;
  UiError? get error;
  bool get isSubmitting;

  void setIntent(WriteIntent intent);
  Future<WriteIntent?> prepare(WritePreparer prepare);
  Future<void> cancel();
  Future<WriteCommitResult?> confirm();

  Future<WriteIntent?> prepareForUi(
    WritePreparer prepare, {
    required WriteOperation expectedOperation,
  });
  Future<void> cancelForUi();
  Future<WriteOutcome?> confirmForUi();

  void invalidate();
}

typedef WriteFlowController = WriteCoordinator;
```

上述类体列出接口合同，不是要求增加未实现的声明。实现时用一个私有 `_prepare`、`_cancel`、`_confirm` 路径供新旧入口委托：

- 旧 `prepare/cancel/confirm` 保留 `BackendException` 类型、原 code 和原返回类型；异常重新构造为 `BackendException(code)`，不透传 `detail`。
- `prepareForUi/cancelForUi` 把同一私有路径的已过滤异常转成 `UbaaErrorMapper.fromCode(code)`，只向 UI 抛出安全 `UiError`。
- `_confirm` 返回局部 record，含 `WriteOutcome` 与原 backend 错误 code；旧 `confirm` 用原 code 构造 `BackendException`，否则返回原 result；`confirmForUi` 只返回同一个安全 outcome，不再抛业务异常。原 code 不能从 UiError 反推，因为现有 mapper 会把 `parseError` 展示合并为 `upstreamChanged`。
- 未开始操作、重复点击、已销毁或生命周期失效后的完成返回 `null`，不创建错误消息；过期保持旧合同，返回 `null` 且 state.error 为 `intentExpired`，commit 次数为零。
- 未知 Dart 异常在同一实现中转成 `internalError`，消费后的 intent 必须清除。用独立 RED 记录对旧控制器遗漏的修复，不允许把原异常带到安全完成结果。
- `DateTime Function()? now` 只用于确定性过期测试；默认 `DateTime.now`，不修改 Core 过期权威。
- `bool Function()? canStart` 是 AppController 的会话转换门禁，默认允许；prepare、confirm、兼容 setIntent 在开始前检查，发布 preparing/committing 通知后、实际外部调用前再次检查。cancel/discard 不受阻，仍可清理已有 intent。

`write_controller.dart` 显式导出 `WriteCoordinator`、三个旧 typedef 和别名。保留 `WriteFlowController.new`、旧 getter 和方法 tear-off 的现有编译合同，并新增类型身份测试，确保没有两个类或两个状态机。

### 4.3 UI 三个命令

```dart
typedef WritePreparationRunner = Future<WriteIntent?> Function(
  Future<WriteIntent> Function() prepare, {
  required WriteOperation expectedOperation,
});
typedef WriteCancellationRunner = Future<void> Function();
typedef WriteConfirmationRunner = Future<WriteOutcome?> Function();
```

`UbaaMainShell` 新增 `writeState`（默认 `const WriteState.idle()`）、`onRunWritePrepare`、`onCancelWrite`、`onConfirmWrite`。默认状态只支持无写入的展示，不创建备用状态机；任何写入口都同时要求完整命令能力。

保留 `onPrepareBykcWrite` 等领域 typed prepare callback，让 UI 继续收集 typed action、表单及位置/照片输入。`_startX` 将该 callback 封装为 prepare closure，再委托 `onRunWritePrepare` 并传当前入口的精确 `expectedOperation`。`null` 表示未开始或已失效，不能被 UI 当成 prepare 失败弹第二次提示。

旧 `onCommitWrite/onDiscardWriteIntent/onWriteSuccess/onVerifyCgyyReceipt/onVerifyCgyyCancellation/onRefreshYgdkAfterWrite/onRefreshEvaluationAfterWrite` 的实际运行职责收回 app/host 配置。本阶段可保留旧 Shell 字段用于兼容构造、能力与 wiring 合同，但生产 UI 不再调用这些字段；其可执行路径只接受新三个命令。既有公开 callback typedef 继续导出，避免无必要地删除名字。

UI 的 `_confirmWrite` 只 await `onConfirmWrite`，检查 mounted/outcome 是否非空，然后显示 outcome.message；原消息投影收归 app。`_cancelWrite` 和 `_prepareWrite` 只转发及显示原有失败提示。保持当前 SnackBar 文案和显示位置，不因为新增 state.error 而未经测试添加另一张错误卡；独立 `WriteConfirmationView(error: ...)` 的既有合同不变。

### 4.4 回读配置

`WriteReceiptVerifier` 是 app 内的一个具体 helper，构造参数只接受现有能力：通用领域 refresh、Cgyy receipt 匹配、Cgyy cancellation 双回读、Ygdk 原路线回读、Evaluation 原路线回读。参数直接使用现有 domain DTO 和函数类型，不要求 UI/domain 导出全局后端接口。

它提供以下具体入口，coordinator 在 commit 结果已闭合后调用：

```dart
Future<WriteOutcome> complete(
  WriteIntent intent, {
  WriteCommitResult? result,
  UiError? error,
  required bool Function() isCurrent,
});
```

每次额外回读开始前检查 `isCurrent()`；coordinator 在 helper 返回后再检查代次，失效则不向 UI 返回 outcome。helper 不改变 result 的 success/outcomeUnknown，不重试写入，也不保存 pending/receipt。

## 5. 唯一状态机规则

| 触发 | 状态与结果 | 必须证明的调用行为 |
|---|---|---|
| prepare | idle -> preparing -> ready；失败回 idle 并保存安全 error | prepare 期间 commit 为零；重复 prepare 不调用第二次后端 |
| 操作类型不匹配 | best-effort discard，回 idle，安全错误 | expectedOperation 与 intent.operation 不同不能显示确认页或提交 |
| cancel | ready -> cancelling；成功 idle，失败仍 ready | 等待 discard 后才清理；失败可重试取消，不能并发 confirm |
| confirm | ready -> committing -> readingBack -> idle | 进入 committing 时锁定一次消费；快速双击、重入及晚到 setIntent 都不能重复发送 |
| 过期 | 保留 ready intent 和安全 intentExpired | commit 为零；取消仍可释放；不依赖 UI 的按钮禁用代替状态机检查 |
| 确定失败 | 清除 intent，返回 result | 不把 success=false 改为异常；不自动重试 |
| outcomeUnknown | 清除 intent，完成指定只读回读后返回安全 outcome | 确认不可再次消费；读取成功也不能把未知写结果提升为成功 |
| 未知异常 | 清除消费后的 intent，映射 internalError | 原异常不逃逸；同 intent 不重试 |
| invalidate | 同步提升 generation 并移除可提交 intent | 待确认 intent best-effort discard；在途提交不能撤回，不发补偿写请求 |
| dispose | 同步失效，禁止后续通知或结果交付 | 晚到 prepare 必须使用原 discard 释放，晚到 commit 不触发新会话回读 |

用单调 generation 标记会话归属，用一个异步操作 ticket 识别当前正在完成的调用；ticket 是异步所有权标记，不是第二套 pending 状态。`finally` 只能结束自己拥有的操作，不能清除新代次的 state。

在途操作失效时使用 `invalidating`，保持不可重入直至该操作结束；失效前 intent 不再可见。旧操作最终结束只允许把仍由自己占用的 invalidating 转回 idle，不能恢复 ready 或显示旧错误。该规则避免旧 commit 尚未结束时同一 coordinator 又开始另一项写入。AppController 重建新 backend 时可以创建新的 coordinator，但旧实例已永久 retire，不再是生产当前实例。

## 6. 领域回读矩阵

| 场景 | 回读条件与顺序 | 完成结果 |
|---|---|---|
| Bykc/Signin/Libbook | success 或 outcomeUnknown 时按原 operation/readbackQuery 调用通用 refresh | refresh 失败不改变已闭合写结果 |
| Cgyy 预约 | 先刷新订单列表；仅确定成功且有 receipt 时再匹配收据 | cgyyReceiptVerified 保持 true/false/null；未知结果不得借 receipt 升级 |
| Cgyy 取消 | 只走 intent.readbackQuery 内有效 orderId 的双回读，expectedRoute 固定 intent.resolvedRoute | 无 query、无能力、错误均 false；不降级为普通单列表刷新 |
| Ygdk | success 或 outcomeUnknown 时按 intent 原路线调用概览+记录回读 | ygdkReadbackAttempted 只说明是否调用过，异常也不能解释为已核对；确定上传失败不补最终提交 |
| Evaluation | success、outcomeUnknown、存在 batch result 的确定失败、以及 commit 错误时均按 intent 原路线回读 | 保持 Phase 11J 的部分成功/失败/未知/未尝试结果；不重排、不补交、不从回读结果重写提交结果 |
| result.operation 与 intent 不符 | 转为安全 outcomeUnknown，再按原 intent.operation 走对应回读 | 不使用错误 operation 的领域或路线 |

先从 Phase 11J 最终代码逐项抄录当前条件，测试精确调用顺序。所有 callback 抛错都由 helper 做 best-effort 处理；读错误不触发 commit。原 UI 中中文消息投影与核对标志一起收归 receipt_verifier，UI 不再决定未知结果、记录号或收据提示语义。

## 7. 生命周期和 backend 绑定

AppController 暴露只读 `WriteCoordinator get writeCoordinator`，持有当前实例并转发其通知。Host 继续监听 AppController，不缓存另一份 WriteState。创建 coordinator 时将 commit/discard 绑定到当时的具体 backend 对象，不能捕获会在以后读取 `this._backend` 的动态方法，否则晚到 prepare 会把旧 intent 交给新 backend 清理。

现有 `commitWrite/discardWriteIntent` 的输入与能力检查保留。用 AppController 内最小私有方法接受显式 backend 参数，供旧公开方法与 coordinator 的固定 backend closure 共用；不新增跨包 backend adapter。

- 在有效 `setRoutePolicy` 开始修改路线、`submitLogin` 真正开始登录、`logout` 开始注销之前同步调用 `invalidate()`。未改变路线的 no-op、不进入登录的输入拒绝不需要创建额外代次。
- 所有 session/backend 转换在失效通知前关闭 `canStart`，覆盖整个 backend await，并在 finally 恢复。AppController 以私有转换计数处理初始化内嵌自动登录及并发转换，计数不保存 intent；先完成其中一项不能使另一项尚在途时提前开放写入。
- `rebuildBackend` 通过现有前置条件后，先让旧 coordinator 失效；replacement 确定可用时从 AppController 移除旧监听并 dispose 旧 coordinator，再绑定新 backend 创建当前 coordinator。
- session 失效进入 login、清空当前账户及 `dispose` 同步失效。使用已有 session/phase/reset 集中边界，避免在每个读取异常分支重复添加协议判断。
- 注销、重登录和切路线不必等待在途写 HTTP 结束；它们必须立即撤销 UI 的消费资格。不可取消的 HTTP 最终结果只允许留在旧调用中，不触发新会话回读和消息。
- AppController 自身的 `_lifecycleEpoch` 继续保护已发出的只读请求。coordinator 在回读前后的代次检查不能替代 AppController 对回读晚到结果的检查。
- Host 的位置获取也属于 generic prepare closure 内部；获取期间失效后不得接着用新会话发起旧 action 的 prepare。给 prepare closure 一个开始前已绑定的后端/生命周期检查，检查点位于平台能力 await 之后、业务 prepare 之前。

最后一项通过 host 测试用位置 Completer 卡住流程，注销后完成位置返回，断言业务 prepare 为零；不能只测试 prepare 已经建立 intent 后的释放。

## 8. UI 测试迁移方案

采用父任务允许的最小方案：`ubaa_ui/pubspec.yaml` 仅在 `dev_dependencies` 添加 path `ubaa_app: ../ubaa_app`，更新 UI 自身 lock。它用于测试真实实现，不加入 UI `dependencies`，UI 的 `lib/` 仍只能导入 domain/Flutter。app 不反向依赖 UI，不新增运行依赖环。

在 `test/support/write_harness.dart` 建立 `_WriteHarness` StatefulWidget，使用测试提供的原 commit/discard/readback callback 创建真实 `WriteCoordinator`，通过 AnimatedBuilder 将 state 与三个安全方法传给 Shell，并在 dispose 中 dispose coordinator。该文件是由 `widgets_test.dart` 独立 import 的测试支持库；原 `widgets/` part 注册顺序不变。新增的 `write_coordination_test.dart` 独立测试 Shell 的状态与命令合同。

```dart
// 下列片段仅展示接线；实际 Shell 构造仍转发全部既有参数。
Widget build(BuildContext context) => AnimatedBuilder(
  animation: _coordinator,
  builder: (context, _) => UbaaMainShell(
    writeState: _coordinator.state,
    onRunWritePrepare: _coordinator.prepareForUi,
    onCancelWrite: _coordinator.cancelForUi,
    onConfirmWrite: _coordinator.confirmForUi,
    // 其余参数由 widget.shell 原样转发。
  ),
);
```

原 `widgets_test.dart` 及其 part 中的 `MaterialApp(home: UbaaMainShell(...))` 统一改为 `MaterialApp(home: coordinatedShell(...))`。该函数保留原 Shell 参数形状并构造 `_WriteHarness(shell: UbaaMainShell(...))`，原领域 prepare/commit/refresh fake、Completer、调用计数和断言保持不变。harness 接收原 raw commit/discard/readback，领域 prepare 继续传给 Shell。

同一个 `coordinatedShell` 构造覆盖原行为、查询、首页及 golden，避免测试按当前是否写入分叉接线。它只增加测试组合层，不修改生产 Widget 树内部布局。只测试 `WriteConfirmationView` 展示的既有用例继续直接构造该公开组件；新的命令合同测试直接构造 `UbaaMainShell` 并显式注入状态和命令。

Ygdk 动态能力测试的外部 ValueNotifier 继续控制领域 prepare/photo callback 是否为 null；harness coordinator 身份在同一次挂载中保持不变。commit/discard 使用稳定转发 closure，在调用时读取最新 `widget.shell`；`didUpdateWidget` 不重建 coordinator，以免能力变化时丢弃待确认意图。`_HarnessReceiptVerifier` 继承真实 `WriteReceiptVerifier`，仅将其五个 nullable callback getter 委托到最新 Shell；缺失能力仍返回 null，不能用非空 no-op closure 虚报 Ygdk 已尝试回读。

harness 禁止保存 intent/error/submitting、判断 operation、决定回读、推导成功或处理重试。它可封装原 callback 到 `WriteReceiptVerifier` 的构造，但不能复制 helper 的算法。UI 生产源码不导入 app/bindings，测试不会调用 `RustLib.init` 或 `createProductionBackend`，fake callback 不发真实请求。

## 9. 可执行任务

### 任务 A：固定旧合同和生产接线 RED

文件：原 `write_controller_test.dart`、新 `write_coordinator_test.dart` 与对应叶、`ubaa_host/test/ubaa_app_host/callbacks.dart`、`packages/ubaa_app/test/public_api_contract_test.dart`。

- [x] 以已提交 `4b0dcb0` 保存原有测试源码基线，Phase 11J 的完整 Flutter 与 integration 已通过；与本阶段逐字核对测试叶和 golden SHA-256，见任务 E。
- [x] 新增 Shell 状态消费接口 RED；缺少 `WriteState/WritePhase` 及 Shell 的 `writeState` 参数时编译失败，见 `/tmp/ubaa-write-ui-red.log`。Host 的唯一协调器接线另由真实行为测试验证，不把它记作未实际执行的 Host RED。
- [x] 新增完整命令能力 RED：分别缺少 prepare、cancel、confirm 时仍出现“准备选课”，3 项预期失败见 `/tmp/ubaa-write-capabilities-red.log`；实现完整命令门禁后通过。
- [x] 新增旧 `confirm` 的未知异常消费 RED：commit 抛 `StateError('/private/token=secret')`，断言原 intent 清除、第二次 confirm 不调用 commit、异常闭合为 `BackendException(internalError)`、安全状态不包含输入字符串。
- [x] 对已发现的同步通知重入、过时结果交付、旧异常 code、会话转换窗口和第二次回读缺口先观察行为 RED，再作最小修复；具体失败见第 11 节，不把仅作回归覆盖的测试追记为 RED。

核心测试示例：

```dart
test('提交开始后双击确认只调用一次且未知异常消费意图', () async {
  final release = Completer<WriteCommitResult>();
  var calls = 0;
  final coordinator = WriteCoordinator(commit: (_) {
    calls++;
    return release.future;
  });
  coordinator.setIntent(freshIntent());
  final first = coordinator.confirmForUi();
  expect(await coordinator.confirmForUi(), isNull);
  release.completeError(StateError('/private/token=secret'));
  final outcome = await first;
  expect(calls, 1);
  expect(outcome?.error?.code, UbaaErrorCode.internalError);
  expect(coordinator.state.intent, isNull);
  expect(await coordinator.confirmForUi(), isNull);
  coordinator.dispose();
});
```

示例中的 `freshIntent()` 在实际测试根入口命名为 `_intent()`，构造固定 ID、固定路线、未来过期时间、无敏感信息的现有 WriteIntent。使用固定 `now`，不依赖系统时钟或真实等待。

### 任务 B：Domain 和 App 状态机

产出：第 4 节精确接口、兼容别名、唯一状态实现及安全回读；消费现有 domain DTO 和 AppController 行为。

- [x] 创建 domain state/outcome，显式导出；为 phase 派生属性、结果/错误互斥和稳定类型身份补最小测试。
- [x] 创建 coordinator；先实现 prepare/cancel/confirm 同步门禁和状态转换，再补 generation、ticket、失效与 dispose。
- [x] 把原 UI 的回读条件与顺序放进 `receipt_verifier.dart`，由 coordinator 唯一调用；保持第 6 节矩阵。
- [x] 把 `WriteFlowController` 改为同一实现的 typedef，保留旧路径及方法 tear-off 合同；新安全入口只映射结果，不再实现状态。
- [x] 在 AppController 创建和绑定 coordinator，添加生命周期失效；固定具体 backend 的 commit/discard closure。
- [x] 运行 App/Domain focused 与公共 API 合同，确认旧 `BackendException` 用例继续通过；人工核对 UI/Host 尚未切换时没有生产副作用。

### 任务 C：Host/UI 与原测试接线

消费：任务 B 的 domain 类型、coordinator safe methods 和 AppController getter；产出唯一生产状态消费路径。

- [x] UI 添加三个命令及 state 参数，保留领域 typed prepare callback；写按钮完整能力检查改为新命令集合。
- [x] Host 把 AppController 当前 coordinator 的状态/安全方法传给 Shell；位置 prepare 在平台 await 后核对原 coordinator 与准备阶段。照片输入保留原表单 mounted 与能力检查。
- [x] 删除 UI 四个状态字段及其赋值；删除 UI 的回读调度，将 confirm 缩为 await outcome、mounted 检查和既有提示。
- [x] 添加 UI 测试 dev dependency、真实 `_WriteHarness` 和统一 `coordinatedShell` 构造迁移；保留原断言，golden 通过普通比较模式验证。
- [x] Host 测试证明真实 coordinator 的状态驱动 UI 并只提交一次；AppController 生命周期测试证明 logout/route/backend rebuild 后旧确认失效、新会话不消费旧结果。
- [x] 原 UI 消息行为测试在真实 coordinator 下继续通过：准备失败、取消失败、确定业务失败、未知结果、Cgyy 预约/取消核对、Ygdk 记录提示、Evaluation 部分结果。

### 任务 D：必需测试矩阵

所有异步竞态使用 Completer，不使用真实 HTTP、人工 sleep 或真实账号。

- [x] prepare 只准备不提交；重复 prepare 和 setIntent 不覆盖 pending；expectedOperation 不符只 discard 一次。
- [x] cancel 等待释放；失败仍可取消；缺失 discard 与未知异常只暴露安全 code；cancel 中 confirm 为零。
- [x] confirm 前精确过期边界；提交期间重复确认；成功、业务失败、outcomeUnknown、BackendException、UiError 及未知 Object 均不能复用消费后的 intent。
- [x] 第 6 节各领域回读由 app 顺序测试与原 UI 行为测试覆盖；回读失败与 receipt 不匹配不改变 result；结果 operation 错配按原 intent 核对。
- [x] prepare/cancel/commit/readback 四个 await 阶段分别 invalidate/dispose；晚到事件不通知、不显示、不清除新代次状态。8 个组合的文件映射见第 11 节。
- [x] 切换 backend 后晚到 prepare 只 discard 原 backend；旧 commit 完成不调用新 backend 或新 session 的回读。
- [x] 位置/照片等待期间注销后，后续业务 prepare 为零；照片用例在等待期间注销，完成选择并继续填写完整的原表单后仍不 prepare/commit。原 Ygdk 能力消失的确认阻止测试继续通过。
- [x] 新旧控制器名字是相同实现；旧异常/方法签名继续可用；新 UI 面不出现 BackendException/detail/原异常。
- [x] 以 Ruby YAML 结构化读取确认 UI `dependencies` 无 app/bindings，`dev_dependencies.ubaa_app.path` 为 `../ubaa_app`；扫描 UI `lib/**/*.dart` 无相应 import/export，例外明确限于测试。

### 任务 E：验证、复审和阶段提交

- [x] 完整 `just flutter-check` 使用固定 Flutter SDK，通过 7 个范围的 analyze/test；补齐时序覆盖后的最终复跑共 374 项测试，UI 的测试依赖已写入本包 pubspec 与 lock。
- [x] `scripts/check/flutter-workspace.sh` 在每个 package 的 cwd 执行 `pub get --enforce-lockfile`；已通过的完整 Flutter 日志包含 UI 的 lock 强制校验。
- [x] 逐字比较 `4b0dcb0` 的 14 个原 UI 测试叶：只替换构造名称，原测试内容、断言、集合和顺序相同；26 张 golden 的名称、长度与 SHA-256 完全一致，PNG diff 为零。
- [x] macOS integration 7 项通过，证明 `Flutter -> shared host -> coordinator -> AppController` 原宿主行为不回归。
- [x] `just refs`、`just layout-check`、`just check-sensitive`、`just check`、`CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1 just flutter-codegen-check`、`just flutter-check`、`git diff --check` 全部通过。
- [x] FRB 生成零漂移；widgets baseline 按经审查的行为修改更新为 3883 行，Phase 12 再删除该唯一违例。
- [x] macOS、Android APK、iOS simulator Debug 构建和三个产物结构检查通过；DevEco 26.0.0.821/API26、OHOS arm64 动态库与无签名 HAP 门禁通过。本阶段证据不代替最终候选 HEAD 的 Phase 14 证据。
- [x] 独立复审确认唯一状态机、旧公共合同、生命周期 backend 绑定、回读顺序、无 fake 状态机、无新生产依赖和 golden 零差异；完整命令能力问题经三项 RED/GREEN 修复，无遗留高/中问题。
- [x] 父设计/计划、status 和 decision log 已记录实际证据，随精确暂存审查后的 `refactor(flutter): 统一写入状态机` 提交；UI 大规模物理移动留在 Phase 12。

任务 B 的 domain/app 实现与任务 C 的 host/UI 实现可由不同执行者依据本计划并行准备；后者在接口落地后运行真实测试，最终阶段统一验证。共享公共文件、lock 和测试根入口必须指定唯一编辑者，避免并行覆盖。

## 10. 完成判定

生产 UI 和 AppController 没有第二套 pending/receipt 状态，所有 prepare/cancel/confirm 都进入一个当前 coordinator；旧 `WriteFlowController` 是同一实现而非备用路径。原行为测试和 golden 保留，新增竞态/兼容/接线测试通过，完整确定性、宿主与生成门禁有本阶段证据。尚未完成 Phase 12 的 UI 拆分及 Phase 14 的最终候选验证时，不能宣称整轮代码组织已经完成。

## 11. 已取得的局部证据

- Domain 新类型的 RED 为缺失类型/文件；实现后固定 SDK 的 state 与公共 API focused 为 10 项通过。
- 旧确认入口未知异常 RED 实际抛出 `StateError`，不是所需 `BackendException(internalError)`；现已安全闭合并消费旧 intent。
- preparing/committing 的同步通知重入 RED 均为外部调用实际 1 次、期望 0 次；修复在发布状态后、外部调用前复核代次。
- ready/完成/错误通知同步失效 RED 分别返回旧 intent、旧 outcome、抛过时 UiError；修复在结果交付或抛错前再次检查代次。
- 旧接口全错误码矩阵 RED 显示 `BackendException(parseError)` 被 UI mapper 改为 `upstreamChanged`；局部 record 现独立保留原 code，三个旧入口继续逐项通过，UI 保持原安全展示映射。
- canStart RED 显示转换门禁关闭时仍返回完成结果；现准备、确认与兼容 setIntent 均拒绝启动。AppController 的延迟注销/路线转换及同步通知重入另有生产接线测试。
- AppController getter 缺失 RED 后完成唯一持有接线；Cgyy 列表 await 后的注销/路线变更 RED 均为详情调用实际 1 次、期望 0 次，现已在第二读前检查生命周期。
- 固定 `/Users/moorefoss/Dev/flutter-3.41.9/bin/flutter test --reporter expanded` 在 `packages/ubaa_app` 当前工作树为 171 项通过；domain 全包 25 项通过，app analyze 无问题，敏感扫描检查 782 个文件并通过。
- Shell 接口 RED 的原始日志 `/tmp/ubaa-write-ui-red.log` 显示缺失 `WriteState/WritePhase/writeState`，不能加载新增接口测试；完整命令能力 RED 日志 `/tmp/ubaa-write-capabilities-red.log` 显示缺少三个命令各导致一项失败，合计 3 项。上述路径是本机本轮执行证据，不作为仓库永久测试输入。
- 已核对 `/tmp/ubaa-write-flutter-check.log`：domain 25、platform 42、app 171、UI 95、bindings 15、Host 17、官方 Flutter app 2，共 367 项通过，7 个范围 analyze 无问题。该结果包含原 UI/golden 普通比较模式及新增 Host/命令能力测试，不代表 Rust、FRB codegen、integration、本机产物、最终候选或远端 CI 已验收。
- 后续新增 `write_coordinator_dispose_test.dart` 的 6 项 characterization 首次运行即通过，分别证明 cancel、commit、readback 在等待期间 dispose 后，成功及失败的晚到结果都不通知、不交付、不恢复意图；commit 不补偿释放、不回读，readback 不继续第二次收据核对。未因此修改生产代码，也不把这些成功基线记作 RED。
- Host 新增照片等待注销的 Completer characterization，实际打开阳光表单、输入时间、开始照片选择，注销使原 Shell 卸载后才返回照片并点击“继续确认”；业务 prepare 与 commit 均为零。首次运行即通过，未修改生产代码。
- 上述补充后重新运行 app 全包 177 项、Host 全包 18 项测试，全部通过；两个新增测试范围的 `dart analyze` 无问题，精确文件 `git diff --check` 通过。此前 367 项完整 Flutter 日志仍按执行时的测试数量保留，不将单包补充回归冒充另一次完整门禁。
- 最终 Flutter 复跑 `/tmp/ubaa-write-flutter-check-final.log`：domain 25、platform 42、app 177、UI 95、bindings 15、Host 18、官方 app 2，共 374 项通过，全部格式、静态分析与锁文件强制校验通过。
- `/tmp/ubaa-write-codegen.log` 为 FRB 零漂移，`/tmp/ubaa-write-integration.log` 为 macOS 7 项通过；`/tmp/ubaa-write-{macos,android,ios,ohos}-build.log` 记录本机三平台构建和 OHOS API26 无签名 HAP，三个官方平台另经 `just flutter-artifact-check` 通过。构建产生的本机元数据差异已按精确路径检查并恢复，不提交本机 SDK 路径。
- `/tmp/ubaa-write-rust-check-final.log` 为完整 Rust/Shell/CLI 门禁退出码 0；前一轮因新文档命令漏写 `--locked` 被既有 CLI 合同拦截，修正文档后整套重跑通过，未修改测试绕过合同。

| 等待阶段 | invalidate 证据 | dispose 证据 |
|---|---|---|
| prepare | `write_coordinator/invalidation.dart`：晚到 prepare 释放原意图且不恢复确认页 | 同文件：销毁后的 prepare 返回只清理且没有通知 |
| cancel | `write_coordinator/invalidation.dart`：取消期间失效不重复释放且晚到失败不恢复意图 | `write_coordinator_dispose_test.dart`：晚到成功/失败均不重复释放或通知 |
| commit | `write_coordinator/invalidation.dart`：提交期间失效不回读、不显示晚到结果、不补偿提交 | `write_coordinator_dispose_test.dart`：晚到成功/失败均不回读或交付结果 |
| readback | `write_coordinator/invalidation.dart`：回读期间失效不执行第二次收据核对且不交付结果 | `write_coordinator_dispose_test.dart`：晚到成功/失败均不核对收据或交付结果 |
