# 当前开发成果整合与组合回归

日期：2026-10-01至2026-10-02（Asia/Shanghai）。在主目录新建`codex/project-completion-20261001`，从`d7c37f73`快进纳入离线分支`e1af4360`，再合并按钮分支`31a7d750`的已提交成果。原三个worktree及其未提交源码/文档保留；本文件属于本次合并候选的证据，不覆盖后续新功能候选。

## 整合结果

- 完整保留离线首页、后台恢复、十二领域加密缓存和写后生命周期；恢复旧版博雅三维筛选/完整详情/跨启动偏好、图书馆逐日日程、macOS Keychain、登录选项及语义按钮。
- 博雅在线与持久读取都保留来源明确的分类/校区，完整详情的联系人/电话只在线展示；图书馆逐日日程复用同次响应并通过缓存专用返回值公开，旧CLI及旧Bridge分区详情字段不变。
- 解决21项组合行为失败：旧读取接线、手动密码恢复、迟到凭据/资料、退出与替换、保存/清除顺序。保留旧版功能与新离线生命周期，裁决见[决策](../decision-log.md)。
- Bridge升级v37并重新生成；CLI v10、Session v2、配置v1不变，缓存schema v6通过默认可选字段兼容原内容。
- 按结构门禁把两项凭据测试归到平台`test/credentials/`。另清理仅计划worktree的80 MB旧Flutter build；非链接、无跟踪文件且无占用核对后删除，保留原源文件与未提交工作。

## 当前门禁

`just refs`、`just layout-check`、`just contract-version-check`、`just check-sensitive`、`just check`（含CLI二进制端到端16项）、`just flutter-check`、`just flutter-codegen-check`和macOS Debug构建全部通过。七包测试数为57/92/598/331/26/79/75，总计1258，静态分析无问题。macOS构建有系统legacy Keychain API弃用警告；不影响构建，未关闭交互策略保护或TLS。

| 类别 | 仓库外日志 | SHA-256 |
|---|---|---|
| Rust/CLI完整门禁 | `<private-evidence>/legacy-tmp/ubaa-consolidation-full-check3-20261001.log` | `c80a3122b1ac83500b712ff849a71d8a22aa5be15df43069bb41df59d0ee6df7` |
| Flutter七包1258项与分析 | `<private-evidence>/legacy-tmp/ubaa-consolidation-full-flutter2-20261001.log` | `fb39f5faabb0029938b536e0313fb258ab3d624753c8955226889f27712da0d6` |
| FRB零漂移 | `<private-evidence>/legacy-tmp/ubaa-consolidation-codegen-check-20261002.log` | `29063bdcf4962eb7dbf36303bd3c806720ae2c385578437c6f7eec590155f91f` |
| macOS Debug构建 | `<private-evidence>/legacy-tmp/ubaa-consolidation-macos-build-20261001.log` | `c765b32421012afe9af79719e9939aeee3c198d999bf63d9d57e37fa9788b095` |
| 组合行为首次失败 | `<private-evidence>/legacy-tmp/ubaa-consolidation-behavior-red-20261001.log` | `7e1166f784fe4bd6113e6b626af3e12d615cb6dbb477615e3b7416d4cef79d00` |
| 登录与完整详情32项 | `<private-evidence>/legacy-tmp/ubaa-consolidation-focused2-20261001.log` | `d2665310ab98aadb2ec6a0724a0ebac152675d4105b9d9871ecb35d7194da959` |
| Core缓存44项 | `<private-evidence>/legacy-tmp/ubaa-consolidation-core-caches-20261001.log` | `4d61f3a6c1947b4ff5852c2fa46202ee1620f82b5cac921e53008ca186278c83` |

## 实际运行与剩余范围

已用私有隔离`UBAA_CONFIG_DIR`打开本候选macOS生产App。Computer Use实际调用返回“Mac is locked”，因此仅记录启动与锁屏阻塞；登录、真实界面、按键、筛选和跨进程恢复均不能据此标PASS。已请求手动解锁，等待期间继续独立任务。

WebVPN Core-live另行运行并记录，不运行Direct；图书馆目前在营业窗口外，须尊重原适用性判定。真实学校写入0，敏感输入未复制或提交。

交互验证码仍在原macOS worktree未提交，门锁专用显示和统计开关误报待后续修复；研究生课表等当前冻结源新增差异待专项核对。最终三端原生与逐按钮清单仍待，整体项目未完成。
