# package_info_plus_ohos

仅分发 CPF-Flutter/flutter_plus_plugins 固定提交 9571de239933ab2893dbd49037e128135b050a7c 的 package_info_plus 原生 OHOS 实现，保留版权与许可证，原文件摘要见 UPSTREAM.json。官方五端继续用 pub.dev 发布版，不导入上游旧 Dart 门面或降级依赖。

本地差异：当前 Flutter HAR 路径；移除原生日志；网络结果适配标准 List 接口、补失败传播与订阅代次/解除；包信息通过标准 getAll 通道。实现不访问学校会话。原生设备验证与构建分开记录；待上游独立 OHOS 分发支持当前接口后可替换本目录。
