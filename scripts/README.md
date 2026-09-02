# 脚本入口与副作用

所有稳定入口由仓库根 `justfile` 暴露；脚本内部按副作用分类。除 `bootstrap/` 和 `live/` 外，验证脚本不得主动
访问真实上游。运行时凭据、会话、验证码、原始响应和签名材料不得写入仓库或 CI artifact。

| 分类 | 稳定 recipe | 脚本 | 网络与写入边界 |
|---|---|---|---|
| bootstrap | `just refs-bootstrap` | `bootstrap/references.sh` | 唯一允许联网并创建缺失冻结引用的入口；已有路径只校验，不覆盖、不拉取 |
| check | `just refs` | `check/references.sh` | 纯只读校验 remote、HEAD 和干净工作树；缺失时失败并提示 bootstrap |
| check | `just layout-check` | `check/layout.sh` | 检查手写文件行数、目录拥挤度和 baseline；不访问网络或凭据 |
| check | `just check-sensitive` | `check/sensitive.sh` | 只读取待提交/未忽略文件，不读取 `.env.local` 或运行会话 |
| check | `just flutter-check` | `check/flutter-workspace.sh` | 官方 Flutter 依赖解析、Dart format、analyze 和 test；只访问依赖源 |
| check | `just flutter-codegen-check` | `check/flutter-codegen.sh` | 重生成 FRB 后要求受跟踪生成目录零漂移 |
| build | `just flutter-build` | `build/flutter.sh` | 构建明确官方平台；不签名、不安装、不访问真实账号 |
| build | `just ohos-check` | `build/ohos.sh` | 检查 OHOS 工具链并构建 HAP；签名与无签名模式由显式环境控制 |
| live | `just verify-live` | `live/verify.sh`、`live/core-live.sh` | 唯一真实账号入口；只允许 direct/webvpn，凭据仅经 stdin，真实写入需另行授权 |
| release | `just release-preflight` | `release/preflight.sh` | 只使用纯 refs 校验并生成无凭据报告；要求工作树干净 |
| release | `just flutter-artifact-check` | `release/verify-flutter-artifact.sh` | 只读检查本地产物结构和摘要，不签名、不安装 |
| tests | `just shell-check`、`just check` | `tests/{layout,references,live-launchers}.sh` | 临时目录内的确定性合同；不访问真实上游 |

`lib/repo.sh` 只提供从任意当前目录定位仓库根的函数；`lib/live-features.sh` 只提供两个 live 入口共同使用的
功能白名单。两者没有独立 CLI，也不拥有网络或凭据。
