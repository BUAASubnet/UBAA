# F01—F07 工程质量整改

日期：2026-10-11。基线 a0a1736031e9e380eedb9c70b27e26224a5f5793；分支 codex/engineering-quality-20261011。

## 基线事实

工作区干净，纯 refs 校验通过：old 1f4b8f8412272b6a423d4ad92b396e3db721e6f3、buaa-api a63712fa2ae0a6c8066197063ddee98e3a6b5b81。10 月 9 日 Windows Rust 作业 113661413049 因 cache/files.rs 的 unused_mut 失败；Linux 原生作业 113661424999 因缺少 libsecret-1 开发依赖失败。其余作业通过不替代这两个平台。

F03/F04 是源码确认的条件性风险；当前没有真实事故复现。F05 是状态所有权债务，F06 是初始化错误分类丢失，F07 是源码摘要范围不足。

## 验证账本

本轮外部私有日志目录为 UBAA-private-evidence/engineering-repair-20261011。所有测试仅使用合成数据，不读取学校账号或真实会话。历史证据不作为本轮通过结论。


## 实现与反例

| 审查项 | 最终实现 | 本轮行为证据 |
|---|---|---|
| F01 | Unix 才声明可变 DirBuilder，Windows 保留不可变构造；不降低 lint | 基线 Windows 作业实际 RED；修复分支的实际 Windows 作业单独登记 |
| F02 | Linux 补 libsecret-1-dev；独立 XDG/D-Bus 会话覆盖 Secret Service 可用/不可用 | 插件锁定源码的 CMake 要求已核对；Linux 实际构建与运行门禁待候选作业 |
| F03 | FRB open 异步；进程 Mutex/内核排他锁共用 2 秒预算；保留锁文件与 CAS 修订 | 原双进程启动超过 5 秒 RED；修复后有界失败、解锁可恢复；真实 macOS FFI 同时验证加载帧、资源忙页面和重试登录 |
| F04 | 发送观察独立于收尾标记；发送后 panic/未分类 Dart 异常归约 unknown，原路线回读，意图不重放；Dart 成功投影后才确认持久提示 | Rust 与 Dart 生效后异常先 RED；108 项 Bridge 写回归 GREEN；补测提示容量耗尽后 panic 的材料错误丢失，RED 后保留 Capacity；发送前 panic 不误判已发送 |
| F05 | SessionLifecycleOwner 私有拥有后端/代次/退出/重建/销毁；CacheLifecycleOwner 私有拥有读/离线代次与清理；原字段改为只读查询，跨模块使用命令 | GradeBaselineOwner 可独立验证等待期间换账号、写入迟到、退出/重建后能力永久失效；不实例化 AppController，不新增通知权威 |
| F06 | BridgeInitializationError 白名单原因；UnavailableBackend 保留分类；本地诊断保留枚举与编号，启动页可重新打开 | 配置/会话损坏不会删除原材料；Host 五类失败/重试、迟到实例释放、加载帧与异常脱敏 7 项通过；Host 全包 101 项通过 |
| F07 | 全部 Git 跟踪输入摘要、工作区干净状态、候选 SHA、作业链接及产物相对路径摘要 | Core/Cargo.lock/构建脚本变化不改变旧清单的 3 个反例及缺工具链反例先 RED；3 项新行为合同 GREEN |

新增 caller-pinned 入口在路线矩阵中逐项登记：博雅已选、图书馆预约列表和今日课堂。原有五项固定路线检查保留，新增三项同样要求一次 guard、一次 runtime_for、一次 finish_caller_pinned，禁止 Auto 解析与回退。只读 DTO 继续生成到唯一 canonical read.dart，不放宽原生成边界测试。

持续高频会话写入可合法触发新的资源忙结果。原快照/修订并发合同仅在白名单 ResourceBusy 时重试未取得锁的本地操作，设置测试整体进展期限；成功读取仍逐次比较快照与修订，其他错误立即失败。生产锁预算仍为 2 秒，学校请求没有新增重试。

## 本地验收与边界

- 七包 Flutter 格式、分析及 1354 项完整回归通过：Domain 57、Platform 84、App 653、UI 353、Bindings 31、Host 101、官方宿主 75；原黄金图片未修改。
- 默认 macOS 原生五入口共 12 项通过：网络 1、真实普通插件 2、应用流程 7、FFI 缓存 1、双进程启动 1。窗口无法前置的提示仍存在，这不是人工逐按钮或真实账号验收。
- OHOS 无签名 Debug HAP、arm64 动态库与插件源码合成合同通过；不代表实体 HUKS 或正式签名验收。
- FRB 2.13.0 生成零漂移通过；Bridge 升至 v41，CLI v11、Session v2、配置 v1、缓存 v6 保持。
- 源码候选的 Windows/Linux 与其余原生 CI、干净候选 preflight 及最终提交将在收尾追加。

原生持锁夹具最初在 App 内启动 Python，被 Sandbox 正确拒绝；最终使用外部宿主与应用新建的合成标记协调，应用权限不变。初始化错误必须在测试主体断言，避免测试工厂内的断言被生产错误处理捕获而遮蔽诊断。所有日志仅在仓库外，未保存学校响应、凭据或 UI 媒体到 Git。


本地严格 Rust/CLI/Shell 门禁已通过，包含 CLI E2E、Clippy -D warnings、测试、构建及文档。后续容量异常修复另跑全写 108 项与全工作区 Clippy 通过。来源、layout、敏感扫描、module/集成清单及公开合同门禁通过。首个阶段提交 f6bd5159 修复 F01/F02 与 F07；运行边界改动作为跨 Rust/FRB/Dart 的同一阶段提交，避免出现不匹配的中间 Bridge ABI。
