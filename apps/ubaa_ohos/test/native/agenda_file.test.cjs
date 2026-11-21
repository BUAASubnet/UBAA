// 执行实际 ArkTS 插件，验证保存面板授权的路径和一次性选择。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');
const {createTestTempDirectory} = require('../../../../scripts/tests/test_tmp.cjs');
const ts = require(process.env.UBAA_TYPESCRIPT);
const root = path.resolve(__dirname, '../../../..');
const sourcePath = path.join(root, 'apps/ubaa_ohos/ohos/entry/src/main/ets/platform/AgendaFilePlugin.ets');
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021},
}).outputText;
function fixture(t, mode = 'local') {
  const directory = createTestTempDirectory('ubaa_ohos_agenda_file');
  let plugin;
  t.after(() => {
    try {
      plugin?.onDetachedFromEngine({});
    } finally {
      fs.rmSync(directory, {recursive: true, force: true});
    }
  });
  const destination = path.join(directory, '报告.txt');
  const host = mode === 'media' ? 'media' : 'docs';
  const uri = 'file://' + host + encodeURI(destination) + (mode === 'remote' ? '?networkid=synthetic' : '');
  class FileUri {
    constructor(value) {this.url = new URL(value);}
    get path() {return decodeURIComponent(this.url.pathname);}
    get authority() {return this.url.host;}
    get scheme() {return this.url.protocol.slice(0, -1);}
    isRemoteUri() {return this.url.searchParams.has('networkid');}
  }
  let shared;
  const core = {fileIo: {
    accessSync: fs.existsSync, mkdirSync: fs.mkdirSync, listFileSync: fs.readdirSync,
    statSync: value => ({mtime: fs.statSync(value).mtimeMs / 1000}),
    unlinkSync: fs.unlinkSync, OpenMode: {READ_WRITE: 1, CREATE: 2, TRUNC: 4},
    openSync: value => ({fd: fs.openSync(value, 'w')}),
    writeSync: (fd, bytes) => fs.writeSync(fd, Buffer.from(bytes)),
    closeSync: file => fs.closeSync(file.fd),
  }, fileUri: {FileUri, getUriFromPath: value => 'file://' + value}, picker: {
    DocumentSaveOptions: class {},
    DocumentViewPicker: class {async save(options) {assert.equal(options.autoCreateEmptyFile, false);return [uri];}},
  }};
  const moduleValue = {exports: {}};
  vm.runInNewContext(compiled, {module: moduleValue, exports: moduleValue.exports, require(name) {
    if (name === '@kit.CoreFileKit') return core;
    if (name === '@kit.ArkTS') return {util: {}};
    if (name === '@kit.AbilityKit') return {};
    if (name === '@kit.ArkData') return {uniformTypeDescriptor: {UniformDataType: {FILE: 'general.file'}}};
    if (name === '@kit.ShareKit') return {systemShare: {
      SharedData: class {constructor(data) {this.data = data;}},
      ShareController: class {
        constructor(data) {this.data = data;}
        async show() {shared = this.data.data;}
      },
      SelectionMode: {SINGLE: 0}, SharePreviewMode: {DEFAULT: 0},
    }};
    if (name === '@ohos/flutter_ohos') return {MethodChannel: class {setMethodCallHandler() {}}};
    throw Error('未声明的平台依赖');
  }});
  plugin = new moduleValue.exports.default({cacheDir: directory});
  plugin.onAttachedToEngine({getBinaryMessenger() {return {};}});
  async function invoke(method, args) {
    return new Promise((resolve, reject) => plugin.onMethodCall({method, args: new Map(Object.entries(args))}, {
      success(value) {resolve(value);},
      error(code) {reject(Object.assign(Error('原生文件授权失败'), {code}));},
      notImplemented() {reject(Error('未实现的入口'));},
    }));
  }
  return {
    destination,
    reportDirectory: path.join(directory, 'diagnostic_reports'),
    get shared() {return shared;},
    share: (name, bytes) => invoke('shareReport', {name, bytes}),
    select: () => invoke('select', {name: '报告.txt', kind: 'binary'}),
    resolveFile: selection => invoke('resolveFile', {selection}),
  };
}
test('本机 docs URI 返回解码路径，未创建文件且选择只能消费一次', async t => {
  const f = fixture(t);
  const selection = await f.select();
  await assert.rejects(f.resolveFile('invalid-selection'), {code: 'expired'});
  assert.equal(await f.resolveFile(selection), f.destination);
  assert.equal(fs.existsSync(f.destination), false);
  await assert.rejects(f.resolveFile(selection), {code: 'expired'});
});
for (const mode of ['remote', 'media']) {
  test(`拒绝非本机 docs 保存 URI：${mode}`, async t => {
    const f = fixture(t, mode);
    await assert.rejects(f.resolveFile(await f.select()), {code: 'unsupported_destination'});
    assert.equal(fs.existsSync(f.destination), false);
  });
}

test('分享诊断使用实际 UTF-8 文件并保留最近附件', async t => {
  const f = fixture(t);
  fs.mkdirSync(f.reportDirectory);
  const expired = path.join(f.reportDirectory, 'UBAA-report-1.json');
  const recent = path.join(f.reportDirectory, 'UBAA-report-2.json');
  fs.writeFileSync(expired, '{}');fs.writeFileSync(recent, '{}');
  fs.utimesSync(expired, new Date(0), new Date(0));
  const report = '{"schema_version":3,"events":[{"upstream_message":"报名失败，该课程人数已满"}]}';
  await f.share('UBAA-report-3.json', new Uint8Array(Buffer.from(report)));
  assert.equal(fs.readFileSync(new URL(f.shared.uri), 'utf8'), report);
  assert.equal(f.shared.utd, 'general.file');
  assert.equal(fs.existsSync(expired), false);
  assert.equal(fs.existsSync(recent), true);
});
