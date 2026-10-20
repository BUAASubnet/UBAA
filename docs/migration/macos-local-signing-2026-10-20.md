# macOS 本机固定开发签名

日期：2026-10-20。基线 `e9805f35`。用户授权使用本机已有证书，修复开发重建后钥匙串重复授权的问题。

## 证据与选择

- 原应用的 `codesign` 输出为 `Signature=adhoc`、`TeamIdentifier=not set`，指定要求仅依赖该构建的 `cdhash`。
- 本机未找到名为 UBAA 的可用签名身份，存在可用 Apple Development 证书；应用标识继续为 `cn.edu.ubaa.ubaaFlutter`。选择开发证书，不采用已撤销的分发证书。
- 本机配置按唯一指纹选定证书，Team ID 从证书主题 `OU` 核对，不从证书显示名称括号内容猜测。个人选择文件被 Git 忽略且权限为 0600。

## 实现

共享 `AppInfo.xcconfig` 可选引入 `LocalSigning.xcconfig`，Runner 的三个构建配置引用统一签名模式变量。缺省仍是 Automatic 与原项目临时身份；本机覆盖为 Manual 和已有开发身份。标准 Flutter、Xcode 和 `just flutter-build` 共用此配置，无构建后重签名补丁。

未修改钥匙串项目或访问控制，未导出私钥，未关闭 App Sandbox、TLS 或权限保护。签名身份切换不能替用户自动更新旧钥匙串授权；旧项目首次由新身份读取时仍可能需要用户确认。按 Apple 的[指定要求说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)，稳定身份使后续更新能够匹配同一应用要求；临时签名则依赖具体构建。

## 验证

- 修改前实际产物不能满足“使用稳定证书身份”的目标；不为配置文字添加自证单元测试。
- Xcode 实际设置：本机配置生效为 Manual、固定开发证书和原 bundle identifier；暂时移除配置后恢复为 Automatic、`CODE_SIGN_IDENTITY = -`，随后恢复本机配置。
- macOS Debug 首次签名构建成功；主程序、框架与动态库通过 `codesign --verify --deep --strict`，App Sandbox 与客户端联网权限通过现有产物门禁。
- 系统私钥访问弹窗由用户完成授权；电脑控制接口禁止操作 SecurityAgent，未绕过这一限制。
- 两次 Debug 构建的指定要求完全一致，要求包含原 bundle identifier、Apple 证书链与固定开发身份，不再依赖 `cdhash`。最终深度签名检查通过；源权限保持，附加项仅为 Xcode 缺省 Debug 调试权限（有无本机配置均启用基础权限注入）。
- `just check-changed` 的完整 Rust/Shell 门禁、七包 1326 项 Flutter 测试、格式分析和 FRB 零漂移全部通过；冻结引用、结构与敏感扫描通过。
- 已沿用原配置目录启动固定签名产物。第一次切换身份时进程在系统沙盒初始化等待，用户确认允许原数据访问后正常进入首页；再次重启直接观察到首页、课表和待办，无需重新输入账号。原数据未迁移或清除。

本轮是本机开发签名，不包含分发、公证、上传或发布。
