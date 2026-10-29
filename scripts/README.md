# 脚本结构与副作用

稳定命令及本地/CI 验收要求只在[开发命令](../docs/development/commands.md)维护，本页说明脚本布局与内部支持文件。工具配置遵守 [AGENTS 工具链规则](../AGENTS.md#项目工具链入口)，网络、缓存和生成副作用见[命令边界](../docs/development/commands.md#网络与写入边界)。

| 目录或文件 | 职责 |
|---|---|
| `bootstrap/` | 显式建立缺失冻结引用或带版本/哈希锁的 Python 质量环境 |
| `check/` | 布局、目录、敏感材料、版本、工具链、依赖闭包、集成登记及按改动检查 |
| `build/` | 官方 Flutter 平台与 OHOS HAP 构建 |
| `live/` | 显式获授权的学校只读验证及离线启动测量，不提供真实业务写入入口 |
| `release/` | 依赖/许可证、源码与产物摘要、macOS 权限和无签名发布前置报告 |
| `tests/`、`tests/checks/` | 临时目录及合成样本中的门禁自测；Flutter 包测试运行器仍保留在 tests 中，分类调整留待后续阶段 |
| `lib/` | 仓库根定位、live 功能白名单及唯一工具配置回退解析器，没有独立网络/凭据所有权 |
| `tools/` | Python 质量环境定位/执行、锁定 requirements 和 CycloneDX schema 上游记录 |
| `integration-tests.json` | 原生、人工和真实入口的类别、平台、runner、环境及 defines 登记 |
| `layout-baseline.txt` | 既有精确结构违例，不得用新增基线掩盖问题 |

`check/dart_sources.py` 是 Dart 指令与源码依赖闭包解析支持；`changed_checks.py` 编排检查计划，`module_graph.py` 和 `integration_catalog.py` 复用解析结果。`sensitive.py` 分别读取 index 和工作区，工具/读取错误失败关闭，不读取被忽略凭据。

`lib/repo.sh` 定位仓库根，`lib/live-features.sh` 提供 live 功能白名单，`lib/toolchain.py` 与 Shell 包装解析工具配置。`tools/environment.sh` 只定位质量 venv，普通 checker 不隐式安装依赖。

`live/offline_startup/` 的 run.py、identity.py、process_start.c 和 analyze.py 分别负责显式测量编排、私有材料标识、进程启动计时和安全汇总。analyze_test.py 使用合成输入。`tests/native/startup_lock_runner.py` 是新建临时目录内的外部持锁夹具，不读取账号、会话或修改应用 Sandbox。

`release/dependency_report.py` 生成依赖/许可材料，`source_manifest.py` 关联全部跟踪输入与可选实际产物；其测试使用临时 Git 仓库，不读取未跟踪凭据。原始 Cargo metadata 只作临时转换输入。

平台合同分别覆盖 Linux 合成安全存储会话、OHOS HUKS 和 connectivity 系统边界；不证明实体设备、学校可达或其他 OHOS 插件已经验证。实际入口、覆盖缺口及 CI 平台范围见[命令清单](../docs/development/commands.md)。自有目录与上游目录例外见[目录命名](../docs/development/directories.md)。
