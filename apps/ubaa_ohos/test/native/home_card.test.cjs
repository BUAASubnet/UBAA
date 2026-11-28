const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');
const assert = require('node:assert/strict');
const ts = require(process.env.UBAA_TYPESCRIPT);
const root = path.resolve(__dirname, '../../../..');
const sourcePath = path.join(
  root,
  'apps/ubaa_ohos/ohos/entry/src/main/ets/homecard/HomeCardStore.ets',
);
const compiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021},
}).outputText;

function load(raw, modifiedAt) {
  const moduleValue = {exports: {}};
  vm.runInNewContext(compiled, {
    module: moduleValue,
    exports: moduleValue.exports,
    JSON,
    Math,
    Array,
    Error,
    TextEncoder,
    require(name) {
      if (name === '@kit.CoreFileKit') return {
        fileIo: {
          readTextSync() { return raw; },
          statSync() { return {mtime: modifiedAt / 1000}; },
        },
      };
      if (name === '@kit.FormKit') return {
        formBindingData: {createFormBindingData: value => value},
      };
      if (name === '@kit.ArkData') return {preferences: {}};
      if (name === '@kit.ArkTS') return {util: {TextEncoder}};
      if (name === '@kit.AbilityKit') return {};
      throw Error(`未声明的平台依赖: ${name}`);
    },
  });
  return moduleValue.exports;
}

const payload = {
  version: 2,
  campusDay: '2026-11-27',
  dateLabel: '11月27日 周五',
  signedIn: true,
  agenda: [
    {title: '课程一', time: '08:00–09:40', location: '主楼 101'},
    {title: '课程二', time: '10:00–11:40', location: ''},
    {title: '课程三', time: '14:00–15:40', location: '主楼 202'},
    {title: '课程四', time: '16:00–17:40', location: ''},
  ],
  homework: [
    {title: '希冀作业', time: '今天 23:59', location: ''},
    {title: 'SPOC 作业', time: '明天 23:59', location: ''},
  ],
  todo: [{title: '博雅报名', time: '今天 18:00', location: ''}],
  weekLabel: '11.23–11.29',
  todayWeekday: 5,
  weekRows: [
    {time: '08:00',
      cells: [
        {title: '周一课', time: '08:00–09:40', location: '主楼 101', color: 1},
        {title: '', time: '', location: '', color: 0},
        {title: '周三课', time: '08:00–09:40', location: '', color: 2},
        {title: '', time: '', location: '', color: 0},
        {title: '', time: '', location: '', color: 0},
        {title: '', time: '', location: '', color: 0},
        {title: '', time: '', location: '', color: 0},
      ]},
  ],
};

const today = new Date('2026-11-26T16:00:00Z');
const context = {filesDir: '/data'};
const read = value => load(JSON.stringify(value)).readViewData(context, today);

test('小卡首轮各显示一条日程、待办和作业，剩余条目仍可查看', () => {
  const view = read(payload);
  assert.deepEqual(Array.from(view.smallItems, item => item.category),
    ['日程', '待办', '作业', '日程', '作业', '日程', '日程']);
  assert.equal(view.smallItems[0].location, '主楼 101');
  assert.equal(view.smallItems[1].title, '博雅报名');
  assert.equal(view.smallItems[2].time, '今天 23:59');
});

test('没有课程时小卡仍显示待办和作业，退出后不保留条目', () => {
  const view = read({...payload, agenda: []});
  assert.equal(view.empty, false);
  assert.deepEqual(Array.from(view.smallItems, item => item.category), ['待办', '作业', '作业']);
  assert.equal(read({...payload, signedIn: false}).smallItems.length, 0);
});

test('课程表卡片读取本周课程并按七天补齐空格', () => {
  const view = read(payload);
  assert.equal(view.weekLabel, '11.23–11.29');
  assert.equal(view.todayWeekday, 5);
  assert.equal(view.weekRows.length, 1);
  assert.equal(view.weekRows[0].time, '08:00');
  assert.equal(view.weekRows[0].cells.length, 7);
  assert.equal(view.weekRows[0].cells[0].title, '周一课');
  assert.equal(view.weekRows[0].cells[2].title, '周三课');
  assert.equal(view.weekRows[0].cells[6].title, '');
  const legacy = read({...payload, weekRows: undefined, weekLabel: undefined,
    todayWeekday: undefined});
  assert.equal(legacy.weekRows.length, 0);
  assert.equal(legacy.todayWeekday, 1);
  const broken = read({...payload, weekRows: [{time: '08:00', cells: [
    {title: '缺字段'}]}]});
  assert.equal(broken.weekRows[0].cells.length, 7);
  assert.equal(broken.weekRows[0].cells[0].title, '');
  const clamped = read({...payload, weekRows: [{time: '08:00', cells: [
    {title: '越界颜色', time: '', location: '', color: 99}]}]});
  assert.equal(clamped.weekRows[0].cells[0].color, 0);
  assert.equal(read({...payload, signedIn: false}).weekRows.length, 0);
});

test('保留超出首屏的日程、作业和待办供滑动查看', () => {
  const view = read({...payload, agenda: [...payload.agenda, ...payload.agenda],
    homework: [...payload.homework, ...payload.homework]});
  assert.equal(view.agendaSmall.length, 8);
  assert.equal(view.agendaLarge.length, 8);
  assert.equal(view.homework.length, 4);
  assert.equal(view.homeworkCount, 4);
});

test('北京时间跨日须隐藏昨日快照，未登录也不交付任何列表', () => {
  const lastMinute = load(JSON.stringify(payload)).readViewData(context, new Date('2026-11-27T15:59:59Z'));
  assert.equal(lastMinute.agendaLarge.length, 4);
  const stale = load(JSON.stringify(payload)).readViewData(context, new Date('2026-11-27T16:00:00Z'));
  assert.equal(stale.largeEmpty, true);
  assert.equal(stale.homeworkCount, 0);
  assert.match(stale.statusLine, /更新/);
  const signedOut = read({...payload, signedIn: false});
  assert.equal(signedOut.agendaSmall.length, 0);
  assert.equal(signedOut.todo.length, 0);
});

test('无日期字段的旧快照使用文件时间判断是否跨日', () => {
  const legacy = JSON.stringify({...payload, campusDay: undefined});
  const sameDay = load(legacy, today.getTime()).readViewData(context, today);
  assert.equal(sameDay.agendaLarge.length, 4);
  const stale = load(legacy, today.getTime() - 1000).readViewData(context, today);
  assert.equal(stale.largeEmpty, true);
});

test('渲染当天快照的三个分类和数量', () => {
  const view = read(payload);
  assert.equal(view.dateLabel, '11月27日 周五');
  assert.equal(view.agendaSmall.length, 4);
  assert.equal(view.agendaLarge.length, 4);
  assert.equal(view.homework.length, 2);
  assert.equal(view.todo.length, 1);
  assert.equal(view.homeworkCount, 2);
  assert.equal(view.todoCount, 1);
  assert.equal(view.empty, false);
  assert.equal(view.largeEmpty, false);
  assert.equal(view.statusLine, '');
  assert.deepEqual(JSON.parse(JSON.stringify(view.agendaSmall[0])), payload.agenda[0]);
});

test('未登录、无日程、损坏快照和旧版本都给出稳定展示', () => {
  const signedOut = read({...payload, signedIn: false});
  assert.equal(signedOut.empty, true);
  assert.equal(signedOut.statusLine, '登录后查看今日安排');

  const empty = read({...payload, agenda: [], homework: [], todo: []});
  assert.equal(empty.statusLine, '今天没有日程');
  assert.equal(empty.largeEmpty, true);

  const corrupt = load('not-json').readViewData({filesDir: '/data'});
  assert.equal(corrupt.empty, true);
  assert.equal(corrupt.agendaSmall.length, 0);

  const oldVersion = load(JSON.stringify({...payload, version: 1}))
    .readViewData({filesDir: '/data'});
  assert.equal(oldVersion.empty, true);

  const longDate = read({...payload, dateLabel: 'x'.repeat(100)});
  assert.equal(longDate.dateLabel.length, 32);
});

test('系统定时回调会重新读取并推送卡片绑定数据', async () => {
  const moduleValue = {exports: {}};
  const abilitySource = path.join(path.dirname(sourcePath), 'HomeCardFormAbility.ets');
  const ability = ts.transpileModule(fs.readFileSync(abilitySource, 'utf8'), {
    compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021},
  }).outputText;
  const updates = [];
  let snapshot = {statusLine: '旧快照'};
  vm.runInNewContext(ability, {
    module: moduleValue,
    exports: moduleValue.exports,
    require(name) {
      if (name === '@kit.FormKit') return {
        FormExtensionAbility: class { context = context; },
        formProvider: {async updateForm(id, data) { updates.push([id, data]); }},
      };
      if (name === './HomeCardStore') return {binding(owner) {
        assert.equal(owner, context);
        return snapshot;
      }};
      throw Error(`未声明的平台依赖: ${name}`);
    },
  });
  const form = new moduleValue.exports.default();
  form.onUpdateForm('test-form');
  snapshot = {statusLine: '新快照'};
  form.onUpdateForm('test-form');
  assert.deepEqual(updates, [
    ['test-form', {statusLine: '旧快照'}],
    ['test-form', {statusLine: '新快照'}],
  ]);
});
