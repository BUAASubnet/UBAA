# 当前目标：统一项目自有目录命名（已完成）

按用户选择统一使用下划线。迁移五个自有目录并同步 Cargo、FRB、原生构建、CI、脚本与文档引用。冻结引用、第三方、Android 资源限定目录和历史证据归档保留原路径。新增目录命名检查，完整确定性门禁和 macOS Debug 构建已通过。规则见 docs/development/directories.md。

验证：冻结引用、目录／布局／敏感检查、just check 全部步骤、1474 项 Flutter 测试与静态分析、FRB 零漂移、macOS Debug 构建通过。macOS／iOS Pods 已更新本地规范校验值，依赖版本未变；未执行其他平台原生运行验收。
