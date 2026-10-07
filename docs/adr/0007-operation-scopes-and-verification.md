# ADR 0007：操作作用域、状态提交与验证闭包

日期：2026-10-07。状态：已实施。依据为[独立工程审查](../migration/engineering-quality-independent-review-2026-10-07.md)，承接 [ADR 0006](0006-explicit-dart-modules.md)。结果与当前候选证据见[实施记录](../migration/engineering-quality-implementation-2026-10-07.md)。

## 问题

显式 library 改善了定位和依赖声明，但仅拆文件不能保证确认路线固定、认证完成错误有终态、异步结果仍属于当前会话。局部 import 图和版本清单也不能证明完整依赖闭包或标准交付材料有效。

## 决定

- 写入的 expected route 在 Core 单次解析内校验；同一 runtime 执行 fresh authority 和最终发送，Bridge 不先检查后重新决定路线。保持一次性 intent、最终至多一次、unknown 禁止重试和独立只读回读。
- 认证完成拥有独立 token，与已释放的验证码 engaged 位分离。所有当前完成失败必须解除 loading 并保留可恢复错误；失效操作不能提交状态。SessionScope/ReadScope 将后端、会话代次和读取缓存代次的校验集中，调用方不能在 helper 已改状态后才补检查。
- 学期结果、在途合并和失效归 AcademicTermsOwner；成绩只依赖 CurrentTermsReader。ControllerReadCaches 汇总领域缓存失效，清理与重建调用同一入口。保留公共 AppController、单个 ChangeNotifier 和唯一 WriteCoordinator；本轮不引入第二套状态框架。
- 普通偏好保存继续拒绝覆盖坏值；用户明确清除按账号键删除，不要求旧内容能解码。凭据、密钥和业务缓存维持各自安全清理合同。
- Session 冲突通过内部 typed cause 分类，展示文案不控制行为；序列化仅保留既有公开字段。Rust 调用方使用 UbaaError::new，新增内部原因不升级 CLI/FRB/磁盘版本。
- 源码政策以自有工作区完整依赖闭包为依据，生成/外部库排除须明确；未支持语法和无法解析输入不能静默当成功。敏感门禁分别读取 index blob 和工作区内容，读取/工具错误失败关闭。
- 交付材料按声明 schema 校验；包版本、许可证来源证据、未知许可项与允许发布的决定分别表达。开发工具显式准备并锁版本/哈希，日常验证不隐式联网安装。

## 取舍与验证

不增加产品运行时框架，继续复用现有 Chrono、Serde、RustCrypto、Cookie 和平台插件。新的所有者只收窄已证实易错的状态边界，不将必要协议/展示DTO合并成万能模型。

先保留失败证据，再分别验证路线交错、认证完成异常、迟到快照、偏好恢复、字段失效与门禁负例。现有各领域资格/正文、缓存、账号和unknown保护仍保留；原生插件通道、设备、真实学校读取和正式发布不能互相替代。

Rust错误类型新增内部状态会限制外部结构体字面量构造；已登记构造函数和序列化形状保持，兼容说明与测试随实现更新。若以后承诺稳定第三方Rust源码API，应将构造方式和破坏性版本策略明确列入公开合同。
