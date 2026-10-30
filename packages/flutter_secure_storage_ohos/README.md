# flutter_secure_storage OHOS插件适配

本地插件提供标准 `plugins.it_nomads.com/flutter_secure_storage` 原生接口；Dart调用复用官方 `flutter_secure_storage_platform_interface 2.1.1`。只有OHOS宿主依赖本包，官方五端继续使用发布的 `flutter_secure_storage 10.0.0`。不在宿主维护另一套安全材料通道。

## 来源与许可证

- HUKS/AES及插件结构：[Csy_Gitee fork](https://gitee.com/Csy_Gitee/flutter_secure_storage)，固定提交 `f1a8ada0a000f3c3d0e2ad51eed3b86b57969652`。
- UTF-8及数组工具：[CPF-Flutter fork](https://gitcode.com/CPF-Flutter/fluttertpc_flutter_secure_storage)，固定提交 `67c7b82e85b08a649dfd4f2bb0c455011a9384fa`。
- 原始文件SHA-256见 `UPSTREAM.json`，保留原版权头。OHOS代码采用Apache-2.0（LICENSE），上游插件BSD许可另存LICENSE-BSD。

## 相对上游修订

1. 不复制旧Dart门面及其Dart<3/interface1.x依赖，声明当前Dart3.11与插件interface2.1.1。
2. 保留社区HUKS RSA-OAEP包装密钥方式，私钥不导出到Preferences；将内容加密固定为AES-256-GCM，采用新v2材料空间，无旧数据迁移。
3. 读写都等待密钥初始化、加解密和flush；串行插件队列覆盖引擎并发；失败返回稳定错误，禁止自动reset及明文降级。
4. 删除上游秘密/系统原始错误日志和算法迁移逻辑；加解密异常有界收尾HUKS会话。
5. 值与其键同置于认证密文中；拒绝损坏、篡改和跨键复制。有密文但密钥丢失时不创建替代密钥，不覆盖原记录。
6. 标准read/write/delete/containsKey/readAll/deleteAll只访问插件自身Preferences；UBAA生产账号清理仍只删除明确键。
7. 使用 `huks.hasKeyItem` 区分密钥存在与缺失，允许首次写入创建密钥；其他系统异常继续报错，有密文时仍禁止生成替代密钥。

## 验证

`bash scripts/tests/secure-storage-ohos.sh`（从仓库根运行）用DevEco TypeScript编译器加载实际ArkTS源码，注入内存Preferences与Node加密系统边界，覆盖错误传播、重开、Unicode、空值、篡改、键绑定、落盘失败及密钥丢失。`just ohos-check mode=debug`自动执行该合同并构建当前OHOS宿主。

这些是确定性合同与构建证据，不等于实际设备HUKS或正式签名验收。设备上的唯一合成键写入、重开读取、删除仍须单独验证。
