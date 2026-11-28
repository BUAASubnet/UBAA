import { common } from '@kit.AbilityKit';
import { formBindingData } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';

export interface HomeCardItem {
  title: string;
  time: string;
  location: string;
}

export interface HomeCardSmallItem extends HomeCardItem {
  category: string;
}

interface HomeCardPayload {
  version: number;
  campusDay?: string;
  dateLabel: string;
  signedIn: boolean;
  agenda: HomeCardItem[];
  homework: HomeCardItem[];
  todo: HomeCardItem[];
}

export class HomeCardViewData {
  dateLabel: string = '';
  agendaSmall: Array<HomeCardItem> = [];
  smallItems: Array<HomeCardSmallItem> = [];
  agendaLarge: Array<HomeCardItem> = [];
  homework: Array<HomeCardItem> = [];
  todo: Array<HomeCardItem> = [];
  homeworkCount: number = 0;
  todoCount: number = 0;
  statusLine: string = '';
  empty: boolean = true;
  largeEmpty: boolean = true;
}

const snapshotFile: string = 'ubaa_home_card.json';
const formStore: string = 'ubaa_home_card_forms';

function snapshotPath(context: common.Context): string {
  return `${context.filesDir}/${snapshotFile}`;
}

function emptyView(statusLine: string): HomeCardViewData {
  const view = new HomeCardViewData();
  view.statusLine = statusLine;
  return view;
}

function parsePayload(raw: string): HomeCardPayload | undefined {
  try {
    const value = JSON.parse(raw) as HomeCardPayload;
    if (value === null || value.version !== 2 || typeof value.dateLabel !== 'string' ||
      (value.campusDay !== undefined && typeof value.campusDay !== 'string') ||
      typeof value.signedIn !== 'boolean' ||
      !Array.isArray(value.agenda) || !Array.isArray(value.homework) || !Array.isArray(value.todo)) {
      return undefined;
    }
    return value;
  } catch (_) {
    return undefined;
  }
}

function campusDateKey(milliseconds: number): string {
  return new Date(milliseconds + 8 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

function appendSmallItem(items: Array<HomeCardSmallItem>, category: string, item: HomeCardItem): void {
  const row: HomeCardSmallItem = {
    category: category,
    title: item.title,
    time: item.time,
    location: item.location,
  };
  items.push(row);
}

export function readViewData(context: common.Context, now: Date = new Date()): HomeCardViewData {
  let raw: string = '';
  try {
    raw = fileIo.readTextSync(snapshotPath(context));
  } catch (_) {
    return emptyView('打开 UBAA 查看今日安排');
  }
  const payload = parsePayload(raw);
  if (payload === undefined) {
    return emptyView('打开 UBAA 查看今日安排');
  }
  if (!payload.signedIn) {
    return emptyView('登录后查看今日安排');
  }
  let snapshotDay = payload.campusDay;
  if (snapshotDay === undefined) {
    try {
      snapshotDay = campusDateKey(fileIo.statSync(snapshotPath(context)).mtime * 1000);
    } catch (_) {
      return emptyView('打开 UBAA 更新今日安排');
    }
  }
  if (snapshotDay !== campusDateKey(now.getTime())) {
    return emptyView('打开 UBAA 更新今日安排');
  }
  const view = new HomeCardViewData();
  view.dateLabel = payload.dateLabel.slice(0, 32);
  view.agendaSmall = payload.agenda.slice(0, 12);
  view.agendaLarge = view.agendaSmall;
  view.homework = payload.homework.slice(0, 12);
  view.todo = payload.todo.slice(0, 12);
  view.homeworkCount = payload.homework.length;
  view.todoCount = payload.todo.length;
  const length = Math.max(view.agendaSmall.length, view.todo.length, view.homework.length);
  for (let index = 0; index < length; index++) {
    if (index < view.agendaSmall.length) appendSmallItem(view.smallItems, '日程', view.agendaSmall[index]);
    if (index < view.todo.length) appendSmallItem(view.smallItems, '待办', view.todo[index]);
    if (index < view.homework.length) appendSmallItem(view.smallItems, '作业', view.homework[index]);
  }
  if (view.smallItems.length === 0) {
    view.statusLine = '今天没有日程';
  }
  view.empty = view.smallItems.length === 0;
  view.largeEmpty = view.agendaLarge.length === 0 && view.homework.length === 0 &&
    view.todo.length === 0;
  return view;
}

export function binding(context: common.Context): formBindingData.FormBindingData {
  return formBindingData.createFormBindingData(readViewData(context));
}

export function saveSnapshot(context: common.Context, payload: string): void {
  const target = snapshotPath(context);
  const temporary = `${target}.tmp`;
  const file = fileIo.openSync(temporary,
    fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  try {
    const bytes = new util.TextEncoder().encodeInto(payload);
    const count = fileIo.writeSync(file.fd, payload);
    if (count !== bytes.length) {
      throw new Error('incomplete snapshot');
    }
  } finally {
    fileIo.closeSync(file);
  }
  fileIo.renameSync(temporary, target);
}

function loadFormIds(context: common.Context): Array<string> {
  try {
    const store = preferences.getPreferencesSync(context, { name: formStore });
    const raw = store.getSync('ids', '[]') as string;
    const parsed = JSON.parse(raw) as Array<string>;
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed.filter((id: string) => typeof id === 'string' && id.length > 0);
  } catch (_) {
    return [];
  }
}

function saveFormIds(context: common.Context, ids: Array<string>): void {
  const store = preferences.getPreferencesSync(context, { name: formStore });
  store.putSync('ids', JSON.stringify(ids));
  store.flush();
}

export function rememberForm(context: common.Context, formId: string): void {
  const ids = loadFormIds(context);
  if (!ids.includes(formId)) {
    ids.push(formId);
    saveFormIds(context, ids);
  }
}

export function forgetForm(context: common.Context, formId: string): void {
  const ids = loadFormIds(context).filter((id: string) => id !== formId);
  saveFormIds(context, ids);
}

export function formIds(context: common.Context): Array<string> {
  return loadFormIds(context);
}
