// 运行实际 ArkTS 源码；仅模拟系统网络与 Flutter 回调，不访问真实网络。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.env.UBAA_TYPESCRIPT);
const root = process.env.UBAA_NETWORK_PLUGIN_SOURCE || path.resolve(__dirname, '../../ohos/src/main/ets/dev/fluttercommunity/plus/connectivity');
const subscriptions = [];
const connection = {
  createNetConnection() {
    const value = { handlers: {}, closed: false,
      on(name, callback) { this.handlers[name] = callback; },
      register(callback) { queueMicrotask(() => callback(undefined)); },
      unregister(callback) { this.closed = true; callback(undefined); },
    };
    subscriptions.push(value);
    return value;
  },
};
function load(name) {
  const source = fs.readFileSync(path.join(root, `${name}.ets`), 'utf8');
  const code = ts.transpileModule(source, {compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021}}).outputText;
  const module = {exports: {}};
  vm.runInNewContext(code, {module, exports: module.exports, require: (name) => {
    if(name === '@ohos.net.connection') return {default: connection};
    if(name === './Connectivity') return {Connectivity: {netConnection: connection.createNetConnection(), CONNECTIVITY_NONE: 'none'}};
    if(name.includes('/Log')) return {default: {d(){}}};
    return {};
  }, console, Promise});
  return module.exports;
}
const tick = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  const Handler = load('ConnectivityMethodChannelHandler').default;
  let result;
  const success = new Handler({getNetworkType: async () => 'wifi'});
  await success.handleCheckResult({success(value) { result = value; }, error() { assert.fail('正常读取不应失败'); }});
  assert.equal(JSON.stringify(result), '["wifi"]');
  const failure = new Handler({getNetworkType: async () => {throw Error('合成失败');}});
  await failure.handleCheckResult({success() { assert.fail('失败不能宣称联网'); }, error(code) { result = code; }});
  assert.equal(result, 'unavailable');
  const Receiver = load('ConnectivityBroadcastReceiver').ConnectivityBroadcastReceiver;
  let release, calls = 0;
  const gate = new Promise(resolve => { release = resolve; });
  const receiver = new Receiver({}, {getNetworkType: () => ++calls === 1 ? gate : Promise.resolve('mobile')});
  const oldEvents = [], newEvents = [];
  receiver.onListen({}, {success(value) {oldEvents.push(value);}, error() {}});
  await tick();
  const old = subscriptions.at(-1);
  receiver.onCancel();
  assert.equal(old.closed, true);
  receiver.onListen({}, {success(value) {newEvents.push(value);}, error() {}});
  await tick();
  release('wifi');
  await tick();
  assert.equal(oldEvents.length, 0);
  assert.equal(JSON.stringify(newEvents), '[["mobile"]]');
  receiver.onCancel();
  subscriptions.at(-1).handlers.netAvailable();
  await tick();
  assert.equal(newEvents.length, 1);
  console.log('OHOS网络插件：列表合同、失败传播、重新订阅与迟到回调隔离通过。');
})().catch(error => { console.error(error); process.exitCode = 1; });
