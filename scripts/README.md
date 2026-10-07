# 脚本入口与副作用

所有稳定入口由仓库根 `justfile` 暴露；脚本内部按副作用分类。除 `bootstrap/` 和 `live/` 外，验证脚本不得主动
访问真实上游。运行时凭据、会话、验证码、原始响应和签名材料不得写入仓库或 CI artifact。

| 分类 | 稳定 recipe | 脚本 | 网络与写入边界 |
|---|---|---|---|
| bootstrap | `just refs-bootstrap` | `bootstrap/references.sh` | 唯一允许联网并创建缺失冻结引用的入口；已有路径只校验，不覆盖、不拉取 |
| check | `just refs` | `check/references.sh` | 纯只读校验 remote、HEAD 和干净工作树；缺失时失败并提示 bootstrap |
| check | `just layout-check` | `check/layout.sh` | 检查手写文件行数、目录拥挤度和 baseline；不访问网络或凭据 |
| check | `just module-check` | `check/module_graph.py` | 聚合 library 尺寸、part 归属和依赖环；纯源码检查 |
| check | `just integration-check/list` | `check/integration_catalog.py` | 入口与登记双向检查、展示分类；不运行学校请求 |
| tests | `just integration-test` | `check/integration_catalog.py` | 只选择已登记的普通原生集合；默认 CI 排除账号和人工入口 |
| tests | `just flutter-test` | `tests/flutter-package.sh` | 固定官方 SDK 的按包/领域普通测试，不访问设备或账号 |
| tests | `just script-test` | Python 门禁与离线统计合同 | 临时目录及合成样本，不创建真实学校客户端 |
| check | `just contract-version-check` | `check/contract-versions.sh` | 纯静态交叉校验 CLI/Bridge 源码常量、JSON Schema、Dart 接受版本与当前文档声明 |
| check | `just check-sensitive` | `check/sensitive.sh` | 只读取待提交/未忽略文件，不读取 `.env.local` 或运行会话 |
| check | `just shell-check` / `just shell-check-strict` | `check/shell.sh` | 均运行 Bash 语法检查；宽松入口缺 ShellCheck 时报告 SKIP，严格入口固定要求 0.11.0 |
| check | `just flutter-check` | `check/flutter-workspace.sh` | 官方 Flutter 依赖解析、Dart format、analyze 和 test；只访问依赖源 |
| check | `just flutter-codegen-check` | `check/flutter-codegen.sh` | 重生成 FRB 后要求受跟踪生成目录零漂移 |
| build | `just flutter-build` | `build/flutter.sh` | 构建明确官方平台；不签名、不安装、不访问真实账号 |
| build | `just ohos-check` | `build/ohos.sh` | 检查 OHOS 工具链并构建 HAP；签名与无签名模式由显式环境控制 |
| live | `just verify-live` | `live/verify.sh`、`live/core-live.sh` | 真实只读矩阵汇总入口；只允许 direct/webvpn，凭据仅经 stdin，真实写入需另行授权 |
| live | `just core-live` | `live/core-live.sh` | 底层只读进程入口；显式路线、stdin 凭据与会话清理规则同上 |
| release | `just release-preflight` | `release/preflight.sh` | 只使用纯 refs 校验并生成无凭据报告；要求工作树干净 |
| release | `just flutter-artifact-check` | `release/verify-flutter-artifact.sh`、`release/macos-entitlements.sh` | 只读检查本地产物结构和摘要；macOS 正式入口固定系统签名/plist 工具读取实际权限并要求 Sandbox 与客户端联网，不签名、不安装 |
| tests | `just check`、`just check-strict` | `tests/{layout,contract-versions,references,flutter-toolchains,maintenance-gates,live-launchers}.sh` | 临时目录内的确定性合同；严格入口要求 ShellCheck，不访问真实上游 |
| tests | `just core-test-contract` | `tests/facade-test-contract.sh` 与根 recipe 中的 Cargo 测试 | 分别验证 Core 默认/测试注入配置及关闭态编译拒绝；不访问真实上游 |

`lib/repo.sh` 只提供从任意当前目录定位仓库根的函数；`lib/live-features.sh` 只提供两个 live 入口共同使用的
功能白名单。两者没有独立 CLI，也不拥有网络或凭据。

`bash scripts/tests/flutter-toolchains.sh` 的八项合同使用临时假 SDK 与 Git，验证完整消费长输出、容纳
冷启动下载进度，并拒绝缺失或错误版本行、版本前缀碰撞、错误 commit 和命令失败；不启动真实 SDK 或下载依赖。

OHOS安全存储合同：`bash scripts/tests/secure-storage-ohos.sh` 读取 `UBAA_DEVECO_HOME` 下的Node与TypeScript，执行插件实际源码的合成系统边界测试；不访问设备、钥匙串或真实账号。`just ohos-check`已包含此检查。

OHOS网络插件合同：`bash scripts/tests/platform-plugins-ohos.sh` 编译实际社区适配源码并模拟系统边界，验证标准列表、失败传播与订阅生命周期；已纳入 `just ohos-check`。
