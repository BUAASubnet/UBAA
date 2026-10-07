// 用注入的插件边界验证真实ArkTS通道；不访问设备或用户安全存储。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.argv[2]);
const source = path.resolve(__dirname, '../../ohos/src/main/ets/components/plugin/FlutterSecureStorageOhosPlugin.ets');
let handler;
let rejectWrites = true, active = 0, peak = 0, writes = 0;
let gate, started;
class Channel {
  setMethodCallHandler(value) { handler = value; }
}
class FailingStorage {
  options = new Map();
  getResetOnError() { return false; }
  async write() {
    if (rejectWrites) throw new Error('合成存储拒绝');
    active++; peak = Math.max(peak, active); writes++;
    started?.();
    await (gate ?? Promise.resolve());
    active--;
  }
  async read() { throw new Error('合成读取拒绝'); }
  async delete() { throw new Error('合成删除拒绝'); }
  async containsKey() { throw new Error('合成查询拒绝'); }
  async readAll() { throw new Error('合成读取拒绝'); }
  async deleteAll() { throw new Error('合成删除拒绝'); }
}
const mod = { exports: {} };
const code = ts.transpileModule(fs.readFileSync(source, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;
vm.runInNewContext(code, {
  exports: mod.exports, module: mod, console,
  require(name) {
    if (name === '@ohos/flutter_ohos') return { MethodChannel: Channel, StandardMethodCodec: { INSTANCE: {} } };
    if (name === './FlutterSecureStorage') return { default: FailingStorage };
    throw new Error('未声明的测试依赖');
  },
});
const plugin = new mod.exports.default();
plugin.onAttachedToEngine({ getBinaryMessenger: () => ({}), getApplicationContext: () => ({}) });
async function call(method, args, target = plugin) {
  return new Promise((resolve, reject) => {
    const deadline = setTimeout(() => reject(new Error('插件未完成回调')), 2000);
    const finish = value => { clearTimeout(deadline); resolve(value); };
    target.onMethodCall({ method, args: new Map(Object.entries(args)) }, {
      success: value => finish({ success: value }),
      error: (code, message, details) => finish({ code, message, details }),
      notImplemented: () => finish({ unsupported: true }),
    });
  });
}
(async () => {
  const result = await call('write', { key: 'fixture-key', value: 'fixture-value', options: new Map() });
  assert.equal(result.code, 'secure_storage_unavailable', '写入失败必须传播，不能报告success(null)');
  assert.equal(result.details, null);
  for (const method of ['read', 'delete', 'containsKey', 'readAll', 'deleteAll']) {
    assert.equal((await call(method, { key: 'fixture-key', options: new Map() })).code, 'secure_storage_unavailable');
  }
  rejectWrites = false;
  const other = new mod.exports.default();
  other.onAttachedToEngine({ getBinaryMessenger: () => ({}), getApplicationContext: () => ({}) });
  const args = { key: 'fixture-key', value: 'fixture-value', options: new Map() };
  const results = await Promise.all([call('write', args), call('write', args, other)]);
  assert(results.every(result => result.success === null));
  assert.equal(peak, 1, '不同引擎的初始化及加解密不得并行');
  const before = writes;
  assert.equal((await call('write', { ...args, options: new Map([['resetOnError', 'true']]) })).code, 'secure_storage_unavailable');
  assert.equal(writes, before);
  plugin.onDetachedFromEngine({});
  assert.equal((await call('write', args)).code, 'secure_storage_unavailable');
  assert.equal(writes, before);
  let release;
  gate = new Promise(resolve => { release = resolve; });
  const began = new Promise(resolve => { started = resolve; });
  const inFlight = call('write', args, other);
  await began;
  const queued = call('write', args, other);
  const activeWrites = writes;
  other.onDetachedFromEngine({});
  other.onAttachedToEngine({ getBinaryMessenger: () => ({}), getApplicationContext: () => ({}) });
  release();
  assert.equal((await inFlight).code, 'secure_storage_unavailable');
  assert.equal((await queued).code, 'secure_storage_unavailable', '旧引擎排队操作不得进入继任引擎');
  assert.equal(writes, activeWrites);
  console.log('OHOS插件通道：六类失败传播、错误后可继续、跨引擎串行、禁止自动重置和卸载保护通过。');
})().catch(error => { console.error(error); process.exitCode = 1; });
