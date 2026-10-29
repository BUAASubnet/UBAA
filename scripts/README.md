# 脚本结构与副作用

稳定命令及本地/CI 验收要求只在[开发命令](../docs/development/commands.md)维护，本页说明脚本布局与内部支持文件。工具配置遵守 [AGENTS 工具链规则](../AGENTS.md#项目工具链入口)，网络、缓存和生成副作用见[命令边界](../docs/development/commands.md#网络与写入边界)。

| 目录或文件 | 职责 |
|---|---|
| `bootstrap/` | 显式安装 CI 固定 Flutter、建立缺失冻结引用或带版本/哈希锁的 Python 质量环境 |
| `check/` | 布局、目录、敏感材料、版本、工具链、依赖闭包、集成登记及按改动检查 |
| `build/` | 官方 Flutter 平台与 OHOS HAP 构建 |
| `live/` | 显式获授权的学校只读验证及历史离线测量分析，不提供真实业务写入入口 |
| `release/` | 依赖/许可证、源码与产物摘要、macOS 权限和无签名发布前置报告 |
| `tests/`、`tests/checks/` | 临时目录及合成样本中的门禁自测；Flutter 包测试运行器仍保留在 tests 中，分类调整留待后续阶段 |
| `lib/` | 仓库根定位、包清单、版本、参数、DevEco、摘要和配置解析支持；凭据只由显式 live 入口读取 |
| `tools/` | Python 质量环境定位/执行、锁定 requirements 和 CycloneDX schema 上游记录 |
| `layout-baseline.txt` | 既有精确结构违例，不得用新增基线掩盖问题 |

`check/dart_sources.py` 是 Dart 指令与源码依赖闭包解析支持；`changed_checks.py` 编排检查计划，`module_graph.py`、`integration_catalog.py` 复用解析结果。`sensitive.py` 分别读取 index 和工作区，工具/读取错误失败关闭，不读取被忽略凭据。

`tools/versions.env` 集中工具和冻结版本，`tools/flutter-packages.json` 集中官方七包清单。`lib/recipe.py` 规范化 recipe 参数，`lib/environment.py` 统一配置语法，`lib/deveco.sh` 和 `lib/checksum.sh` 提供平台布局与摘要兼容。`lib/native_bindings.py` 在关闭 Web 后机械选择 FRB 的 IO 导入。

`lib/repo.sh` 与 `lib/repo.py` 定位仓库根，`lib/live-features.sh` 提供 live 功能白名单，`lib/toolchain.py` 与 Shell 包装解析工具配置。`tools/environment.sh` 只定位质量 venv，普通 checker 不隐式安装依赖。

`live/offline_startup/analyze.py` 与 analyze_test.py 保留历史测量材料的安全统计和合成合同。原生集成登记只保留真实平台能力和 FFI/启动锁，外部持锁程序由应用在自身沙箱派生，自动化缺口见[测试策略](../docs/development/testing.md)。

`release/dependency_report.py` 生成依赖/许可材料，`source_manifest.py` 关联全部跟踪输入与可选实际产物；其测试使用临时 Git 仓库，不读取未跟踪凭据。原始 Cargo metadata 只作临时转换输入。

平台合同分别覆盖 Linux 合成安全存储会话、OHOS HUKS 和 connectivity 系统边界；不证明实体设备、学校可达或其他 OHOS 插件已经验证。实际入口、覆盖缺口及 CI 平台范围见[命令清单](../docs/development/commands.md)。自有目录与上游目录例外见[目录命名](../docs/development/directories.md)。

`integration-tests.json` 只登记保留的原生能力；`tests/native/` 提供注册启动锁夹具及真实独立进程合同，`tests/linux-secure-storage.sh` 在隔离的合成 Secret Service 会话中运行 Linux 能力测试。截图 driver 仍负责将保留用例的媒体写入仓库外。
