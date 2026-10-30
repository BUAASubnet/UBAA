// Hvigor 只读取 OHOS Flutter 生成的 ohos/local.properties；不读环境变量、不调用 Python、不缓存配置。
// 链路：.env.toolchain → just flutter-ohos pub get → local.properties → Cargokit CMake 参数。
const fs = require('node:fs');
const path = require('node:path');

const PREPARE = '请在 apps/ubaa_ohos 运行 just flutter-ohos pub get --enforce-lockfile 后重新构建';

function readLocalProperties(ohosDir) {
    const file = path.join(ohosDir, 'local.properties');
    let text;
    try { text = fs.readFileSync(file, 'utf8'); }
    catch { throw new Error(`缺少 ohos/local.properties。${PREPARE}`); }
    const values = {};
    for (const line of text.split(/\r?\n/)) {
        const match = /^\s*([^#!=\s][^=]*?)\s*=\s*(.*?)\s*$/.exec(line);
        if (match) values[match[1]] = match[2];
    }
    return values;
}

function resolveToolchain(ohosDir) {
    const properties = readLocalProperties(ohosDir);
    const flutterRoot = properties['flutter.sdk'];
    const hmosSdk = properties['hwsdk.dir'];
    for (const [key, value] of [['flutter.sdk', flutterRoot], ['hwsdk.dir', hmosSdk]]) {
        if (!value) throw new Error(`ohos/local.properties 缺少 ${key}。${PREPARE}`);
        // 当前 Hvigor 会按空格拆分 CMake 参数，含空白或分隔符的路径无法正确传给 Cargokit。
        if (!path.isAbsolute(value) || /[\s\0;"\\]/.test(value)) {
            throw new Error(`ohos/local.properties 的 ${key} 必须是不含空白或分隔符的绝对路径`);
        }
    }
    const config = { flutterRoot, nativeSdkRoot: path.join(hmosSdk, 'default/openharmony/native') };
    for (const [root, file, executable] of [
        [config.flutterRoot, 'bin/flutter', true],
        [config.flutterRoot, 'bin/cache/dart-sdk/bin/dart', true],
        [config.nativeSdkRoot, 'llvm/bin/clang', true],
        [config.nativeSdkRoot, 'build/cmake/ohos.toolchain.cmake', false],
    ]) {
        try {
            const target = path.join(root, file);
            if (!fs.statSync(target).isFile()) throw new Error();
            fs.accessSync(target, executable ? fs.constants.X_OK : fs.constants.R_OK);
        } catch { throw new Error(`OHOS 工具链缺少可用的 ${file}。${PREPARE}`); }
    }
    return config;
}

function requireDependencies(appRoot) {
    if (!fs.existsSync(path.join(appRoot, '.dart_tool/package_config.json'))) {
        throw new Error(`缺少 Flutter OH 依赖配置。${PREPARE}`);
    }
}

function nativeArguments(config) {
    return [`-DCARGOKIT_FLUTTER_ROOT:PATH=${config.flutterRoot}`,
        `-DCARGOKIT_OHOS_SDK_HOME:PATH=${config.nativeSdkRoot}`];
}

module.exports = { readLocalProperties, resolveToolchain, requireDependencies, nativeArguments };
