# Flutter 六平台交付与发布流程

更新：2026-10-07。本文规定当前可执行流程，历史候选与旧测试数量见[归档](../migration/history/flutter-release-before-engineering-2026-10-07.md)。当前阶段目标见 [goal.md](../../goal.md)，授权与安全规则见 [AGENTS](../../AGENTS.md#真实账号与验收范围)；历史任务不能授权新的账号请求、签名或发布。

## 候选与证据

为每轮记录源码候选 SHA、工作树状态、工具链、命令、平台/设备、路线、退出码、产物摘要和未执行原因。确定性、原生合成、真实插件通道、设备、Core-live、真实 App、签名/发布独立记账。

先完成并提交源码候选，再在同一候选验证。后续新增纯证据文档必须分别记录文档提交与被验证源码 SHA，不得将旧日志改称新 HEAD 全部通过；任何源码、测试、生成、锁文件或构建配置变化都使对应门禁失效。远端 workflow 以实际 head_sha、job 终态核对，不能以本地 ahead 或历史 run 推断当前 CI。

## 环境准备

首次缺少冻结引用时显式执行 `just refs-bootstrap`；已有引用只运行 `just refs`。质量工具依赖由显式 `just quality-tools-bootstrap` 建立；首次用 `cargo fetch --locked` 预取所有目标、`just flutter-dependencies` 准备七包锁定源码。preflight 不隐式联网安装。官方 Flutter/OHOS、Rust、FRB 固定版本及路径见[平台矩阵](../architecture/flutter-platforms.md)。

## 验收入口

完整确定性清单、原生/发布候选的默认集成集合及平台专项只在[开发命令](../development/commands.md#检查选择与完成条件)维护。按该清单运行并保留实际结果；普通 Flutter、FRB 和原生测试分别记账。原生集合中的插件网络读取/订阅只证明 handler 行为，不证明校园可达。

## 无签名构建与交付材料

在对应 runner 上执行实际目标，不在缺工具平台声称完成：

```bash
just flutter-build platform=macos mode=debug
just flutter-build platform=linux mode=debug
just flutter-build platform=windows mode=debug
just flutter-build platform=android-apk mode=debug
just flutter-build platform=ios-simulator mode=debug
UBAA_OHOS_NO_CODESIGN=1 just ohos-check mode=debug
just flutter-artifact-check platform=android-apk artifact=/绝对路径/app-debug.apk
just release-preflight /仓库外绝对路径/ubaa-release-report
```

`release-preflight` 要求工作树干净、报告目录为空，只运行纯 refs/敏感检查并生成依赖与源码清单；原始 Cargo metadata 仅为自动清理的临时输入，不进入报告。SBOM 必须通过其声明版本的固定 schema 校验；Cargo 元数据是解析依赖图，不自动等于每个平台实际打包集合。Dart/OHOS 许可材料应列出锁定来源、许可证证据及缺失项；包名/版本清单不称作许可批准。默认严格模式遇到材料缺口会保留报告并以状态 3 阻断发布。源码 CI 使用的仅报告模式仍列出缺口，但不能用于判定发布通过；参数与实际边界见[开发命令](../development/commands.md#构建与发布命令)。

产物结构检查覆盖宿主入口、Flutter资源和Rust动态库；macOS还核验实际签名权限。无签名Debug包和HAP不能证明商店签名、安装升级、设备HUKS或正式发布。普通日志、报告和工件不能包含凭据、Cookie、token、原始响应、完整个人资料或本机敏感路径；UI媒体在仓库外私有目录。

## 设备、真实路线与签名

Android/iOS/OHOS实体机权限、前后台、网络订阅及安全材料写读删需要独立设备证据。Core-live/真实App只在当前会话用户已授权的路线和只读范围内执行，空结果、静态回退与Mock不能当作真实按钮验收。真实写入必须有具体操作、目标、路线及时间授权；unknown立即停止，不重试。

正式签名、公证和上传只能在相应授权和环境满足后进行。签名材料由平台安全存储和隔离runner管理，不进入源码、argv、普通日志或artifact；发布前核对候选SHA、校验摘要、许可材料、安装/升级/卸载和平台权限。

## 回退

保存上一份已验证产物、源码/生成/锁文件版本、独立磁盘Session/config/cache schema及兼容说明。失败时停止分发，先判定旧版本能否读取新格式，再回退产物；不能删除用户Session或密钥来掩盖不兼容。数据不可逆或旧版不支持的情形必须标明不能安全自动回退。回退后重新验证原平台启动、离线内容、安全材料和只读恢复，不重放写入。


### 候选输入与产物关联

source-manifest.sha256 覆盖全部 Git 跟踪文件，包括 Core、根 Cargo.toml/Cargo.lock、工具链和构建脚本；未跟踪的凭据与运行目录不会进入清单。build-record.json 将候选 SHA、输入清单摘要和 GitHub 作业关联；原生工作流同时生成 artifact-files.json，使用相对路径及逐文件摘要，避免同一产物因本机绝对目录不同而得到不同内容摘要。外部 SDK、系统库、下载依赖和签名环境仍需按平台登记，这不是可复现构建证明。

## OHOS 补充材料

OHPM 的本地依赖需要区分类型声明和原生产物。受 Git 跟踪、位于本仓库内的纯 `.d.ts` 包记录版本与文件摘要，并沿用项目许可证；这类记录不包含实际动态库。HAR 或其他原生产物通过独立 JSON 材料清单提供来源、摘要、使用方和许可证正文。

运行前设置 `UBAA_OHOS_EVIDENCE` 为清单的绝对路径，再执行 `just release-preflight`。也可以直接给依赖报告生成器传入 `--ohos-evidence`。清单放在仓库外私有目录或被忽略的 `.ubaa_local/`，不要放进要求为空的输出目录。文件路径相对于清单目录解析，也接受绝对路径；绝对路径不会进入输出报告。结构如下，示例摘要和提交必须换成实际值：

```json
{
  "schema": 1,
  "artifacts": [{
    "name": "@ohos/flutter_ohos",
    "version": "实际包版本",
    "artifact": {"path": "flutter_embedding.har", "sha256": "产物的完整 SHA-256"},
    "source": {"repository": "https://example.invalid/source.git", "revision": "40 位源码提交"},
    "references": [{"manifest": "packages/connectivity_plus_ohos/ohos/oh-package.json5", "sha256": "使用方清单的完整 SHA-256"}],
    "licenses": [{"path": "LICENSE", "sha256": "许可证正文的完整 SHA-256"}]
  }]
}
```

同一产物的全部使用方应放入 `references`。工具逐项验证依赖名、使用方清单摘要、产物摘要及非空许可证正文，拒绝失效、重复或相互冲突的映射。相同名称与产物摘要合并为一条记录，保留全部使用方；不同产物不合并。输出保存输入清单摘要和许可证正文副本，并记录来源仓库、提交和版本。

这些来源字段是材料提供方的显式声明。摘要校验能证明本次读取的文件与声明一致，不能独立证明二进制由该源码构建。实际 HAP、动态库架构、签名和构建关联仍按本手册的产物验收执行。缺少清单或某项材料仍阻断严格发布；报告模式只允许材料缺口，格式或摘要错误继续失败。
