# UBAA 官方客户端

UBAA 官方五平台（Windows、macOS、Linux、Android、iOS）Flutter 宿主，同时提供桌面命令模式入口。本页供在本机构建和调试该宿主的开发者使用；从零开始运行 App 见[入门指南](../../docs/development/getting-started.md)。

## macOS 本机开发签名

频繁重建后检查钥匙串功能时，使用固定的本机开发证书，避免临时签名的应用身份随内容变化。

在 `macos/Runner/Configs/LocalSigning.xcconfig` 中设置：

```xcconfig
UBAA_CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = <本机开发证书的 SHA-1 指纹>
DEVELOPMENT_TEAM = <该开发证书所属 Team ID>
```

使用 `security find-identity -v -p codesigning` 查看可用身份，排除被撤销或过期的证书。该配置已被 Git 忽略；不要提交个人证书选择、私钥或钥匙串材料。`just flutter-build platform=macos mode=debug`、直接 Flutter 构建和 Xcode 都会沿用本机选择。

Team ID 取证书主题中的 `OU`，不要把证书显示名称末尾的括号内容当作 Team ID。

没有此文件时，保留共享项目的自动签名与临时身份缺省设置。此配置用于本机开发，不构成分发签名或公证。切换身份后，已有钥匙串项目可能仍需用户为新身份授权一次；不要通过关闭沙盒、删除钥匙串或允许所有应用访问来消除提示。
