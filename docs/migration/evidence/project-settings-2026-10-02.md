# 设置真实性与路线迟到回写修复

日期：2026-10-02。基点`7d1e5cee`。本阶段修复用户可见设置行为，不改变任何学校URL/参数/加密或缓存格式，来源沿[统计对照](../source-parity-ui-telemetry-control.md)与[路线生命周期](../source-parity-ui-route-lifecycle.md)。

## 问题与修复

Noop统计客户端仍可显示开启，App/Host两项新行为测试分别RED；现将实际客户端能力与本地开关分离，生产默认关闭且说明此版本未启用统计，显式配置可用客户端时关闭/再开启仍以白名单事件测试验证。不新增统计服务、SDK或收集字段。

路线先后选择与退出的8项回归中6项RED：旧成功/失败覆盖新选择，再次选择原值被忽略，退出后旧结果恢复路线。现绑定请求修订、凭据修订、生命周期和具体backend，失效回调丢弃。新离线规则本已阻止路线切换在途重建，另两项继续验证收尾后可以重建并读取正确策略。

顺带按职责提取App设置逻辑和UI路线说明弹窗，保持公开入口；不是修改结构门禁阈值。原生缓存集成测试的Bridge版本断言同步为v37。

## 验证

43项App设置/登录/诊断、13项Host统计/接线、拆分后外壳14项及UI静态分析通过。完整Flutter七包为57/92/608/331/26/80/75，共1269项并全部分析通过。`just check`（含CLI端到端16）、引用/结构/版本门禁通过；敏感检查在提交前执行。此阶段未执行Computer Use，真实锁屏仍为阻塞，不从widget推断按钮实操。

| 证据 | 仓库外日志 | SHA-256 |
|---|---|---|
| 路线生命周期RED | `/tmp/ubaa-route-lifecycle-red-20261002.log` | `b6601f071e2845c38b4398515f87e0319bd3e63303ca7e14d4939b578e5b2125` |
| 统计App RED | `/tmp/ubaa-telemetry-red-app-20261002.log` | `bfeaca40675020c6d8a9f82a174fa6145cc4202f35d3f4e643cdd21d65722073` |
| 统计Host RED | `/tmp/ubaa-telemetry-red-host-20261002.log` | `e6ad1190986a71a751a1e8b135ac77ac819a28e05ded49690d45c61ead762a38` |
| 43项聚焦GREEN | `/tmp/ubaa-settings-green-20261002.log` | `fcf66857981341c06a55c531eba7f706e98b86f819ca8992d064159d0308dddb` |
| 完整Flutter1269项 | `/tmp/ubaa-settings-flutter-20261002.log` | `e71b0c04d26b30fa769320a87c25e6b0eda8638a9dbe11a6fb90b6230919e242` |
| Rust/CLI完整门禁 | `/tmp/ubaa-settings-check2-20261002.log` | `45c69bd9c1900bb935ba28ed12999cea8d550fc60b3bd3d6d376381a508121f6` |
| 拆分后外壳14项 | `/tmp/ubaa-settings-shell-green-20261002.log` | `5893e12ab363397847492801d1957ad334c0ae82b2500a17b984a528d9c4f0b0` |
