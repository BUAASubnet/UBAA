/// 无 Flutter Engine 的共享账号、凭据和材料协调入口。
library;

export 'src/credentials.dart';
export 'src/material/secure_material_core.dart';
export 'src/material/material_credentials.dart';
export 'src/local_accounts.dart';
export 'src/material/material_coordination.dart';
export 'src/material/windows_materials.dart';
export 'src/material/linux_secret_service.dart';
export 'src/material/linux_paths.dart';
export 'src/material/windows_dpapi.dart'
    show WindowsDpapiCodec, replaceWindowsMaterial;
