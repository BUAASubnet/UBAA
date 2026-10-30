// Hvigor 配置只来自 local.properties，路径失效或缺项时明确失败，不沿用旧值。
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { resolveToolchain, requireDependencies, nativeArguments } = require('../../tools/ohos_hvigor.cjs');

function sdk(t) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ubaa_hvigor_'));
    t.after(() => fs.rmSync(root, { recursive: true, force: true }));
    const native = 'hmos/default/openharmony/native';
    for (const file of ['flutter/bin/flutter', 'flutter/bin/cache/dart-sdk/bin/dart',
        `${native}/llvm/bin/clang`, `${native}/build/cmake/ohos.toolchain.cmake`]) {
        fs.mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
        fs.writeFileSync(path.join(root, file), '', { mode: 0o700 });
    }
    fs.mkdirSync(path.join(root, 'ohos'));
    return root;
}

function properties(root, text) {
    fs.writeFileSync(path.join(root, 'ohos/local.properties'), text);
}

test('从 local.properties 推出 Flutter 与 native SDK，并生成 CMake 参数', t => {
    const root = sdk(t);
    properties(root, `hwsdk.dir=${root}/hmos\nflutter.sdk=${root}/flutter\nflutter.versionCode=1\n`);
    const config = resolveToolchain(path.join(root, 'ohos'));
    assert.equal(config.flutterRoot, `${root}/flutter`);
    assert.equal(config.nativeSdkRoot, `${root}/hmos/default/openharmony/native`);
    assert.deepEqual(nativeArguments(config), [
        `-DCARGOKIT_FLUTTER_ROOT:PATH=${root}/flutter`,
        `-DCARGOKIT_OHOS_SDK_HOME:PATH=${root}/hmos/default/openharmony/native`]);
});

test('每次重新读取，路径变更后参数随之改变', t => {
    const first = sdk(t), second = sdk(t);
    properties(first, `hwsdk.dir=${first}/hmos\nflutter.sdk=${first}/flutter\n`);
    const before = nativeArguments(resolveToolchain(path.join(first, 'ohos')));
    properties(first, `hwsdk.dir=${second}/hmos\nflutter.sdk=${second}/flutter\n`);
    assert.notDeepEqual(before, nativeArguments(resolveToolchain(path.join(first, 'ohos'))));
});

test('环境变量不参与解析', t => {
    const root = sdk(t);
    properties(root, `hwsdk.dir=${root}/hmos\nflutter.sdk=${root}/flutter\n`);
    const saved = process.env.FLUTTER_ROOT;
    process.env.FLUTTER_ROOT = '/official/flutter';
    t.after(() => { if (saved === undefined) delete process.env.FLUTTER_ROOT; else process.env.FLUTTER_ROOT = saved; });
    assert.equal(resolveToolchain(path.join(root, 'ohos')).flutterRoot, `${root}/flutter`);
});

test('缺文件、缺项、含空白或 SDK 失效时给出准备命令', t => {
    const root = sdk(t);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /缺少 ohos\/local.properties.*pub get/);
    properties(root, `flutter.sdk=${root}/flutter\n`);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /缺少 hwsdk.dir/);
    properties(root, `hwsdk.dir=${root}/hmos\nflutter.sdk=${root}/my flutter\n`);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /空白/);
    properties(root, `hwsdk.dir=${root}/missing\nflutter.sdk=${root}/flutter\n`);
    assert.throws(() => resolveToolchain(path.join(root, 'ohos')), /llvm\/bin\/clang/);
});

test('缺少 Flutter 依赖配置时提示显式准备命令', t => {
    const root = sdk(t);
    assert.throws(() => requireDependencies(root), /pub get --enforce-lockfile/);
    fs.mkdirSync(path.join(root, '.dart_tool'));
    fs.writeFileSync(path.join(root, '.dart_tool/package_config.json'), '{}');
    requireDependencies(root);
});
