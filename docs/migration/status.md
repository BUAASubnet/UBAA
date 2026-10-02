# 当前迁移与交付状态

更新日期：2026-10-02（Asia/Shanghai）。用户已明确恢复整体项目开发与 macOS 真实审查。活动合同见 [goal.md](../../goal.md)。实施分支为 `codex/project-completion-20261001`。

## 已核实的当前事实

- 主目录起点 `d7c37f73`，工作树干净，比 `origin/ubaa2` 多7个本地提交。
- 离线首页分支已提交77项，顶端 `e1af4360`，是主目录的后继；已快进纳入整合分支。原 worktree 的4个未提交文档保持原样。
- macOS 按钮分支11个已提交成果已合并，交互验证码未提交代码已复制整合并补齐当前生命周期，原worktree保持原样。
- 另一 `ui-button-parity` worktree 只有计划/状态改动，保持原样。
- 两冻结来源校验通过：ubaa_old `1f4b8f8412272b6a423d4ad92b396e3db721e6f3`；buaa-api `a63712fa2ae0a6c8066197063ddee98e3a6b5b81`。
- 公开合同当前为 CLI JSON schema v11、Flutter bridge contract v40、Session v2、配置 v1、业务缓存 schema v6；后续整合变更须同步检查。

## 当前实现与验证边界

离线首页、首帧恢复、分批查询、十二领域缓存、成绩基线加密、关联失效与重启核对线索已有实现。旧版按钮分支已实现博雅三维筛选/跨启动偏好、完整详情、图书馆逐日时段及登录/Keychain/语义按钮修复，已纳入当前整合候选。

本轮Rust/CLI完整门禁、1258项Flutter与分析、FRB零漂移、引用/结构/敏感检查及macOS Debug构建通过，见[整合证据](evidence/project-consolidation-2026-10-02.md)。WebVPN Core-live 40项已通过；已启动隔离App，但Computer Use被真实锁屏阻塞，按钮验收待解锁。整体不宣称完成。Direct 按用户网络条件本轮不运行。历史性能与三端测试保留在[接续前状态](history/status-2026-10-01-before-consolidation.md)，不能代替本轮证据。

后续次序：项目整理 → 分支整合 → 剩余行为修复 → 当前门禁与多端适配 → WebVPN 真实读取 → macOS Computer Use 全流程 → 修复复验与交付。


## 2026-10-02设置修复与实时验证

整合提交为`7d1e5cee`。该候选WebVPN Core-live 40 PASS、退出0，真实学校写入0；研讨室用途结果的`static_fallback`仍保留为来源标记，不宣称来自上游。生产App已独立启动，但Computer Use返回Mac锁屏，已请求手动解锁，真实按键未通过。

本阶段继续修复统计开关误报与路线迟到回写，1269项Flutter/分析、Rust/CLI完整门禁及聚焦回归通过，见[设置证据](evidence/project-settings-2026-10-02.md)。该设置阶段提交为`4fda272c`。

## 2026-10-02交互验证码整合

验证码专用Core/Bridge v38/App/Host/UI已接入，补齐原位登录、写保护、后台取消、缓存账号收尾和固定WebVPN就绪接续。完整1299项Flutter/分析、Rust/CLI门禁、敏感检查、FRB零漂移通过；独立私有会话经新交互facade实现WebVPN登录与资料读取，业务写入0。上游未要求验证码，不能宣称真实验证码提交通过。见[阶段证据](evidence/project-interactive-auth-2026-10-02.md)。最新App构建与Computer Use仍待进行，锁屏尚未解除；门锁显示与研究生课表继续开发。

## 2026-10-02门锁专用显示

恢复旧版“查看密码”入口，专用Core页面句柄固定路线并绑定客户端/会话/路线代次；Bridge v39传递白名单，材料不入普通DTO、缓存、日志或JSON。页面30秒刷新前清旧码，手动/定时单飞，隐藏、返回、账号变化或后台立即撤销。手机390和桌面1024宽度Host流程通过，完整1307项Flutter与分析通过。新私有会话WebVPN登录、资料及门锁读取通过，当前真实密码与预约均为空，不宣称有码验收。详细证据见[门锁阶段](evidence/project-lock-display-2026-10-02.md)。

中断后/tmp旧日志已消失；当前阶段门禁重跑并保存在仓库外私有证据目录，保留源码与原worktree。继续开发GSMIS课表，之后再做最新macOS构建与真实按钮核对。旧版Android系统widget及Windows/Linux选图需单独核对，不以macOS测试代替。

## 2026-10-02 GSMIS与时间轴

GSMIS研究生课表与旧版完整节次时间轴已实现，覆盖同会话来源、精确请求、日历核验、相邻课节、空周、离线持久化和三宽度UI。完整1312项Flutter、Rust/CLI门禁、敏感与FRB零漂移通过；当前WebVPN矩阵38 PASS/0 FAIL/退出0，真实账号仅本科来源，GSMIS live仍未取得。详见[阶段证据](evidence/project-gsmis-2026-10-02.md)。下一步补Windows/Linux系统选图接线，再执行最终构建、多端原生验证与Computer Use；整体目标仍在执行。

## 2026-10-02桌面选图与清理

Windows/Linux系统选图已接线，有限读取、取消/重入及文件增长测试通过；官方/OHOS各自锁文件和原生注册已更新。完整1318项Flutter、Rust/CLI门禁、敏感检查与macOS生产构建通过，Win/Linux原生运行未验。两个旧worktree仅清理约47.27GiB可再生构建产物，源码、未提交工作与证据保留。见[阶段证据](evidence/project-desktop-photo-2026-10-02.md)。

继续最终原生矩阵与按钮审查。当前继续会话工具列表未提供Computer Use；上一阶段该工具实际调用被锁屏阻断，225项真实按钮仍不标PASS。将完成可独立进行的原生合成验证、最新版App启动与剩余实现复核，并如实保留外部验收限制。
