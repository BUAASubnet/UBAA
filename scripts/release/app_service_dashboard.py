#!/usr/bin/env python3
"""生成应用服务使用情况看板的 Grafana JSON。

看板经 Infinity 数据源以只读 Token 查询 Cloudflare D1 明细表，数据源 UID 固定为 ubaa-d1。
账号与数据库 ID 不进入仓库，从参数或 UBAA_APP_SERVICE_ACCOUNT_ID、UBAA_APP_SERVICE_D1_ID 读取。
部署步骤见 docs/runbooks/app-service.md。
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys

DS = {"type": "yesoreyeram-infinity-datasource", "uid": "ubaa-d1"}

# 暗色分类色（固定顺序）与状态色
C = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9", "#e66767"]
GOOD, WARN, SERIOUS, CRIT, MUTED = "#0ca30c", "#fab219", "#ec835a", "#d03b3b", "#6e6e6e"

FROM = "date(${__from}/1000,'unixepoch','+8 hours')"
TO = "date(${__to}/1000,'unixepoch','+8 hours')"
TODAY = "date('now','+8 hours')"
RANGE = f"day BETWEEN {FROM} AND {TO}"


def filt(alias=""):
    """平台与渠道筛选。公开面板不替换模板变量，变量原样保留或为空时按“全部”处理。"""
    def one(column, variable):
        value = "'${%s:csv}'" % variable
        return (f"({value}='' OR {value} LIKE '$%' "
                f"OR instr(','||{value}||',', ','||{alias}{column}||',')>0)")
    return f"{one('platform', 'platform')} AND {one('channel', 'channel')}"


FILT = filt()
WHERE = f"{RANGE} AND {FILT}"
DAYS = (f"WITH RECURSIVE d(day) AS (SELECT {FROM} UNION ALL SELECT date(day,'+1 day') "
        f"FROM d WHERE day < MIN({TO},{TODAY}))")
TS = "unixepoch(d.day||'T00:00:00+08:00')*1000 AS time"

FEATURES = [("schedule", "课表"), ("exam", "考试"), ("grades", "成绩"), ("bykc", "博雅课程"),
            ("classroom", "空教室"), ("spoc", "SPOC 作业"), ("judge", "希冀作业"),
            ("libbook", "图书馆"), ("signin", "课堂签到"), ("cgyy", "场馆预约"),
            ("ygdk", "阳光打卡"), ("evaluation", "评教"), ("auth", "登录"), ("app", "应用")]


def case(col, pairs, default=None):
    body = " ".join(f"WHEN '{k}' THEN '{v}'" for k, v in pairs)
    return f"CASE {col} {body} ELSE {default or col} END"


FEAT = lambda col="feature": case(col, FEATURES)
PLAT = case("platform", [("android", "Android"), ("ios", "iOS"), ("ohos", "HarmonyOS"),
                         ("macos", "macOS"), ("windows", "Windows"), ("linux", "Linux")])
CHAN = case("channel", [("github", "GitHub"), ("app_store", "App Store"), ("app_gallery", "华为应用市场")])
KIND = [("input", "输入"), ("authentication", "认证"), ("network", "网络"),
        ("upstream", "上游"), ("parse", "解析"), ("internal", "内部")]
BUCKETS = [("lt_250", "<0.25s"), ("lt_500", "0.25–0.5s"), ("lt_1000", "0.5–1s"),
           ("lt_2000", "1–2s"), ("lt_5000", "2–5s"), ("lt_10000", "5–10s"), ("ge_10000", "≥10s")]
BUCKET_ORDER = "CASE bucket " + " ".join(f"WHEN '{k}' THEN {i}" for i, (k, _) in enumerate(BUCKETS)) + " END"


URL = None


def target(sql, cols, fmt="table", ref="A"):
    return {
        "refId": ref, "datasource": DS, "type": "json", "source": "url", "parser": "backend",
        "url": URL,
        "url_options": {"method": "POST", "body_type": "raw", "body_content_type": "application/json",
                        "data": json.dumps({"sql": " ".join(sql.split())}, ensure_ascii=False)},
        "root_selector": "result[0].results", "format": fmt,
        "columns": [{"selector": s, "text": t, "type": ty} for s, t, ty in cols],
    }


_id = [0]


def panel(kind, title, pos, targets, desc="", defaults=None, overrides=None, options=None, **extra):
    _id[0] += 1
    p = {"id": _id[0], "type": kind, "title": title, "description": desc,
         "gridPos": dict(zip("xywh", pos)), "datasource": DS, "targets": targets,
         "fieldConfig": {"defaults": defaults or {}, "overrides": overrides or []},
         "options": options or {}}
    cols = [c["text"] for t in targets for c in t.get("columns", [])]
    if len(cols) > 1:
        p["transformations"] = [{"id": "organize", "options": {
            "indexByName": {name: i for i, name in enumerate(cols)}, "excludeByName": {}, "renameByName": {}}}]
    p.update(extra)
    return p


def row(title, y, collapsed=False, panels=None):
    _id[0] += 1
    return {"id": _id[0], "type": "row", "title": title, "collapsed": collapsed,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": panels or []}


def color_override(name, color):
    return {"matcher": {"id": "byName", "options": name},
            "properties": [{"id": "color", "value": {"mode": "fixed", "fixedColor": color}}]}


def prop_override(name, *props):
    return {"matcher": {"id": "byName", "options": name},
            "properties": [{"id": k, "value": v} for k, v in props]}


def stat(title, pos, sql, cols, color, desc="", fmt="table", unit="short", spark=False,
         thresholds=None, decimals=0):
    defaults = {"unit": unit, "decimals": decimals,
                "color": {"mode": "fixed", "fixedColor": color} if not thresholds else {"mode": "thresholds"}}
    if thresholds:
        defaults["thresholds"] = {"mode": "absolute", "steps": thresholds}
    return panel("stat", title, pos, [target(sql, cols, fmt)], desc, defaults, options={
        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        "colorMode": "value", "graphMode": "area" if spark else "none", "textMode": "value",
        "justifyMode": "center", "orientation": "auto", "wideLayout": True, "showPercentChange": False})


def ts_defaults(unit="short", draw="line", stack=False, fill=18):
    return {"unit": unit, "decimals": 0, "min": 0,
            "color": {"mode": "palette-classic"},
            "custom": {"drawStyle": draw, "lineWidth": 2, "fillOpacity": fill if draw == "line" else 85,
                       "gradientMode": "opacity" if draw == "line" else "none",
                       "lineInterpolation": "linear", "showPoints": "never", "pointSize": 6,
                       "spanNulls": True, "barAlignment": 0, "barWidthFactor": 0.7,
                       "axisSoftMin": 0, "axisBorderShow": False,
                       "stacking": {"mode": "normal" if stack else "none", "group": "A"}}}


TS_OPTS = {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
           "tooltip": {"mode": "multi", "sort": "desc"}}


def pie(title, pos, sql, label, colors, desc="", value="设备"):
    return panel("piechart", title, pos,
                 [target(sql, [("name", label, "string"), ("value", value, "number")])], desc,
                 {"unit": "short", "decimals": 0, "color": {"mode": "palette-classic"}},
                 [color_override(n, c) for n, c in colors.items()],
                 {"pieType": "donut", "displayLabels": [],
                  "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": True},
                  "legend": {"displayMode": "table", "placement": "right", "showLegend": True,
                             "values": ["value", "percent"]},
                  "tooltip": {"mode": "single", "sort": "none"}})


HBAR = {"orientation": "horizontal", "stacking": "none", "barWidth": 0.45, "groupWidth": 0.7,
        "showValue": "always", "xTickLabelRotation": 0, "fullHighlight": False,
        "legend": {"displayMode": "list", "placement": "bottom", "showLegend": False},
        "tooltip": {"mode": "single", "sort": "none"}}
def build(account_id, database_id):
    """返回看板字典；同一组 ID 多次调用结果相同。"""
    global URL
    for name, value in (('账号 ID', account_id), ('数据库 ID', database_id)):
        if not re.fullmatch(r'[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', value or ''):
            raise ValueError(f'{name}格式无效')
    URL = (f"https://api.cloudflare.com/client/v4/accounts/{account_id}"
           f"/d1/database/{database_id}/query")
    _id[0] = 0
    panels = []
    y = 0

    # ───────── 概览 ─────────
    panels.append(row("概览", y)); y += 1
    daily_active = (f"{DAYS} SELECT {TS}, COUNT(DISTINCT NULLIF(a.user_key,'')) AS users, "
                    f"COUNT(DISTINCT a.install_id) AS devices FROM d LEFT JOIN active_days a "
                    f"ON a.day=d.day AND {filt('a.')} "
                    f"GROUP BY d.day ORDER BY d.day")
    panels += [
        stat("今日活跃", (0, y, 4, 5), daily_active,
             [("time", "时间", "timestamp_epoch"), ("users", "用户", "number"), ("devices", "设备", "number")],
             C[0],
             "今天的去重用户数和设备数，曲线为所选时段每日值。用户只计登记了账号的，设备按安装标识去重。"
             "客户端约每 6 小时上传一次，启动时的首次上传通常还没有账号，所以当天用户数会滞后几小时。",
             fmt="timeseries", spark=True),
        stat("昨日用户", (4, y, 4, 5),
             f"SELECT COUNT(DISTINCT NULLIF(user_key,'')) AS users FROM active_days "
             f"WHERE day=date('now','+8 hours','-1 day') AND {FILT}",
             [("users", "用户", "number")], C[0],
             "昨天（北京时间）登记了账号的去重用户数，不受所选时段影响。完整自然日的数据基本已到齐，比今日数字更能代表日活；7 天内的迟到上传仍可能小幅修订。"),
        stat("时段内用户", (8, y, 4, 5),
             f"SELECT COUNT(DISTINCT NULLIF(user_key,'')) AS users FROM active_days WHERE {WHERE}",
             [("users", "用户", "number")], C[6], "所选时段内去重的活跃用户总数（不是每日之和）。"),
        stat("今日启动", (12, y, 4, 5),
             f"{DAYS} SELECT {TS}, COALESCE(SUM(c.count),0) AS starts FROM d LEFT JOIN counter_days c "
             f"ON c.day=d.day AND c.event='app_started' AND {filt('c.')} "
             f"GROUP BY d.day ORDER BY d.day",
             [("time", "时间", "timestamp_epoch"), ("starts", "启动", "number")], C[1],
             "今天的冷启动次数，曲线为所选时段每日值。", fmt="timeseries", spark=True),
        stat("加载成功率", (16, y, 4, 5),
             f"SELECT CAST(SUM(CASE WHEN result<>'failure' THEN count ELSE 0 END) AS REAL)/NULLIF(SUM(count),0) AS rate "
             f"FROM counter_days WHERE event='feature_loaded' AND {WHERE}",
             [("rate", "成功率", "number")], GOOD,
             "所选时段内功能加载的成功率。空结果（如本学期无考试）按成功计。",
             unit="percentunit", decimals=1,
             thresholds=[{"color": CRIT, "value": None}, {"color": WARN, "value": 0.9}, {"color": GOOD, "value": 0.97}]),
        stat("最近上报", (20, y, 4, 5),
             "SELECT unixepoch(MAX(received_at))*1000 AS t FROM batches",
             [("t", "最近上报", "number")], C[0],
             "服务端最近收到遥测批次的时间，不受筛选影响。长时间没有更新时应检查客户端或 Worker。",
             unit="dateTimeFromNow"),
    ]
    today = next(panel for panel in panels if panel.get("title") == "今日活跃")
    today["options"]["textMode"] = "value_and_name"
    today["fieldConfig"]["overrides"] = [color_override("设备", C[2])]
    y += 5

    # ───────── 活跃 ─────────
    panels.append(row("活跃用户与设备", y)); y += 1
    panels.append(panel(
        "timeseries", "每日活跃趋势", (0, y, 16, 9),
        [target(daily_active, [("time", "时间", "timestamp_epoch"), ("users", "活跃用户", "number"),
                               ("devices", "活跃设备", "number")], "timeseries")],
        "按北京时间自然日去重。没有数据的日期记为 0。",
        ts_defaults(), [color_override("活跃用户", C[0]), color_override("活跃设备", C[2])], TS_OPTS))
    PLAT_COLORS = {"Android": C[2], "iOS": C[0], "HarmonyOS": C[1], "macOS": C[6], "Windows": C[3], "Linux": C[4]}
    panels.append(pie(
        "平台分布", (16, y, 8, 9),
        f"SELECT {PLAT} AS name, COUNT(DISTINCT install_id) AS value FROM active_days WHERE {WHERE} "
        f"GROUP BY platform ORDER BY value DESC", "平台", PLAT_COLORS, "所选时段内各平台的去重活跃设备数。"))
    y += 9
    panels.append(panel(
        "barchart", "版本分布", (0, y, 8, 8),
        [target(f"SELECT app_version AS name, COUNT(DISTINCT install_id) AS value FROM active_days "
                f"WHERE {WHERE} GROUP BY app_version ORDER BY app_version DESC LIMIT 10",
                [("name", "版本", "string"), ("value", "设备", "number")])],
        "所选时段内各版本的去重活跃设备数，最新版本在上。",
        {"unit": "short", "decimals": 0, "min": 0, "color": {"mode": "fixed", "fixedColor": C[0]},
         "custom": {"fillOpacity": 85, "lineWidth": 0, "axisBorderShow": False}},
        options=HBAR))
    panels.append(pie(
        "渠道分布", (8, y, 8, 8),
        f"SELECT {CHAN} AS name, COUNT(DISTINCT install_id) AS value FROM active_days WHERE {WHERE} "
        f"GROUP BY channel ORDER BY value DESC", "渠道",
        {"GitHub": C[6], "App Store": C[0], "华为应用市场": C[1]}, "所选时段内各分发渠道的去重活跃设备数。"))
    panels.append(panel(
        "barchart", "用户年级", (16, y, 8, 8),
        [target(f"SELECT CASE WHEN cohort_type='' THEN '未登记' WHEN cohort_type='unknown' THEN '其他身份' "
                f"WHEN cohort_type='undergrad' THEN '本科 ' || cohort_year ELSE cohort_type || ' ' || cohort_year END AS name, "
                f"COUNT(DISTINCT user_key) AS value FROM active_days WHERE {WHERE} AND user_key<>'' "
                f"GROUP BY cohort_type, cohort_year ORDER BY value DESC LIMIT 10",
                [("name", "年级", "string"), ("value", "用户", "number")])],
        "按学号推断的入学年份与类型统计去重用户。研究生显示学号字母前缀，教职工等无法识别的显示为“其他身份”。",
        {"unit": "short", "decimals": 0, "min": 0, "color": {"mode": "fixed", "fixedColor": C[6]},
         "custom": {"fillOpacity": 85, "lineWidth": 0, "axisBorderShow": False}},
        options=HBAR))
    y += 8

    # ───────── 功能使用 ─────────
    panels.append(row("功能使用", y)); y += 1
    panels.append(panel(
        "barchart", "功能热度", (0, y, 10, 11),
        [target(f"SELECT {FEAT()} AS feature, SUM(CASE WHEN result='success' THEN count ELSE 0 END) AS ok, "
                f"SUM(CASE WHEN result='empty' THEN count ELSE 0 END) AS empty, "
                f"SUM(CASE WHEN result='failure' THEN count ELSE 0 END) AS fail FROM counter_days "
                f"WHERE event='feature_loaded' AND {WHERE} GROUP BY feature ORDER BY SUM(count) DESC",
                [("feature", "功能", "string"), ("ok", "成功", "number"), ("empty", "空结果", "number"),
                 ("fail", "失败", "number")])],
        "所选时段内各功能的加载次数，按结果堆叠。空结果指请求成功但没有内容。",
        {"unit": "short", "decimals": 0, "min": 0, "color": {"mode": "palette-classic"},
         "custom": {"fillOpacity": 85, "lineWidth": 0, "axisBorderShow": False}},
        [color_override("成功", C[0]), color_override("空结果", MUTED), color_override("失败", CRIT)],
        {"orientation": "horizontal", "stacking": "normal", "barWidth": 0.7, "groupWidth": 0.7,
         "showValue": "never", "xTickLabelRotation": 0, "fullHighlight": False,
         "legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
         "tooltip": {"mode": "multi", "sort": "none"}}))
    feat_table_sql = (
        f"WITH c AS (SELECT feature, SUM(count) AS loads, COUNT(DISTINCT install_id) AS devices, "
        f"CAST(SUM(CASE WHEN result<>'failure' THEN count ELSE 0 END) AS REAL)/NULLIF(SUM(count),0) AS rate, "
        f"SUM(CASE WHEN result='failure' THEN count ELSE 0 END) AS fails FROM counter_days "
        f"WHERE event='feature_loaded' AND {WHERE} GROUP BY feature), "
        f"t AS (SELECT feature, CAST(SUM(CASE WHEN bucket IN ('lt_250','lt_500','lt_1000','lt_2000') THEN count ELSE 0 END) AS REAL)"
        f"/NULLIF(SUM(count),0) AS fast FROM timing_days WHERE metric='feature_load' AND {WHERE} GROUP BY feature), "
        f"r AS (SELECT feature, CAST(SUM(CASE WHEN route='webvpn' THEN count ELSE 0 END) AS REAL)/NULLIF(SUM(count),0) AS vpn "
        f"FROM counter_days WHERE event='route_resolved' AND {WHERE} GROUP BY feature) "
        f"SELECT {FEAT('c.feature')} AS name, c.devices, c.loads, c.rate, c.fails, t.fast, r.vpn FROM c "
        f"LEFT JOIN t ON t.feature=c.feature LEFT JOIN r ON r.feature=c.feature ORDER BY c.loads DESC")
    pct_gauge = lambda name: prop_override(
        name, ("unit", "percentunit"), ("decimals", 0), ("min", 0), ("max", 1),
        ("custom.cellOptions", {"type": "gauge", "mode": "basic", "valueDisplayMode": "text"}))
    panels.append(panel(
        "table", "功能明细", (10, y, 14, 11),
        [target(feat_table_sql, [("name", "功能", "string"), ("devices", "使用设备", "number"),
                                 ("loads", "加载次数", "number"), ("rate", "成功率", "number"),
                                 ("fails", "失败", "number"), ("fast", "2 秒内完成", "number"),
                                 ("vpn", "经 WebVPN", "number")])],
        "成功率含空结果；“2 秒内完成”来自功能加载耗时分桶；“经 WebVPN”为线路解析走 WebVPN 的占比。",
        {"custom": {"align": "auto", "cellOptions": {"type": "auto"}, "inspect": False, "minWidth": 60},
         "decimals": 0, "unit": "short",
         "thresholds": {"mode": "absolute", "steps": [{"color": C[0], "value": None}]},
         "color": {"mode": "thresholds"}},
        [prop_override("功能", ("custom.width", 96)), prop_override("使用设备", ("custom.width", 76)),
         prop_override("失败", ("custom.width", 56)),
         prop_override("加载次数", ("custom.cellOptions", {"type": "gauge", "mode": "basic", "valueDisplayMode": "text"}),
                       ("color", {"mode": "fixed", "fixedColor": C[0]})),
         {**pct_gauge("成功率"), "properties": pct_gauge("成功率")["properties"] + [
             {"id": "thresholds", "value": {"mode": "absolute", "steps": [
                 {"color": CRIT, "value": None}, {"color": WARN, "value": 0.9}, {"color": GOOD, "value": 0.97}]}}]},
         {**pct_gauge("2 秒内完成"), "properties": pct_gauge("2 秒内完成")["properties"] + [
             {"id": "color", "value": {"mode": "fixed", "fixedColor": C[2]}}]},
         {**pct_gauge("经 WebVPN"), "properties": pct_gauge("经 WebVPN")["properties"] + [
             {"id": "color", "value": {"mode": "fixed", "fixedColor": C[6]}}]},
         prop_override("失败", ("custom.cellOptions", {"type": "color-text"}),
                       ("thresholds", {"mode": "absolute", "steps": [{"color": "text", "value": None},
                                                                      {"color": CRIT, "value": 1}]}))],
        {"showHeader": True, "cellHeight": "sm", "footer": {"show": False},
         "sortBy": [{"displayName": "加载次数", "desc": True}]}))
    y += 11

    TOP = [("schedule", "课表"), ("judge", "希冀作业"), ("spoc", "SPOC 作业"), ("signin", "课堂签到"),
           ("bykc", "博雅课程"), ("ygdk", "阳光打卡"), ("exam", "考试")]
    cols = ", ".join(f"COALESCE(SUM(CASE WHEN c.feature='{k}' THEN c.count END),0) AS {k}" for k, _ in TOP)
    other = ",".join(f"'{k}'" for k, _ in TOP)
    panels.append(panel(
        "timeseries", "每日功能加载", (0, y, 16, 9),
        [target(f"{DAYS} SELECT {TS}, {cols}, COALESCE(SUM(CASE WHEN c.feature NOT IN ({other}) THEN c.count END),0) AS other "
                f"FROM d LEFT JOIN counter_days c ON c.day=d.day AND c.event='feature_loaded' AND "
                f"{filt('c.')} GROUP BY d.day ORDER BY d.day",
                [("time", "时间", "timestamp_epoch")] + [(k, v, "number") for k, v in TOP] + [("other", "其他", "number")],
                "timeseries")],
        "每日功能加载次数，按功能堆叠。成绩、空教室、图书馆、场馆预约、评教合并为“其他”。",
        ts_defaults(draw="bars", stack=True),
        [color_override(v, C[i]) for i, (_, v) in enumerate(TOP)] + [color_override("其他", MUTED)],
        TS_OPTS))
    panels.append(pie(
        "访问线路", (16, y, 8, 9),
        f"SELECT CASE route WHEN 'direct' THEN '直连' WHEN 'webvpn' THEN 'WebVPN' ELSE route END AS name, "
        f"SUM(count) AS value FROM counter_days WHERE event='route_resolved' AND route<>'none' AND {WHERE} "
        f"GROUP BY route ORDER BY value DESC", "线路", {"直连": C[0], "WebVPN": C[6]},
        "所选时段内线路解析结果的次数占比。WebVPN 占比升高通常意味着用户在校外。", value="次数"))
    y += 9

    # ───────── 使用时段（分钟级） ─────────
    panels.append(row("使用时段", y)); y += 1
    MFILT = FILT
    SPAN = "(${__to}-${__from})"
    BUCKET = (f"CASE WHEN {SPAN}<=21600000 THEN 60000 WHEN {SPAN}<=172800000 THEN 300000 "
              f"WHEN {SPAN}<=691200000 THEN 600000 WHEN {SPAN}<=2764800000 THEN 3600000 ELSE 86400000 END")
    B = "(SELECT b FROM p)"
    OFF = 28800000
    MIN_FROM = "strftime('%Y-%m-%dT%H:%M',${__from}/1000,'unixepoch','+8 hours')"
    MIN_TO = "strftime('%Y-%m-%dT%H:%M',${__to}/1000,'unixepoch','+8 hours')"


    def minute_sql(cols, where):
        # 先汇总为时间桶，阻止连接展开后为每个时间点重复扫描分钟明细。
        return (f"WITH RECURSIVE p(b) AS (SELECT {BUCKET}), "
                f"k(t) AS (SELECT ((${{__from}}+{OFF})/{B})*{B}-{OFF} UNION ALL SELECT t+{B} FROM k "
                f"WHERE t+{B} <= MIN(${{__to}}, unixepoch('now')*1000)), "
                f"m AS (SELECT ((unixepoch(minute_at||':00+08:00')*1000+{OFF})/{B})*{B}-{OFF} AS t, event, feature, result, SUM(count) AS count "
                f"FROM minute_counts WHERE minute_at BETWEEN {MIN_FROM} AND {MIN_TO} AND {MFILT} AND {where} "
                f"GROUP BY t, event, feature, result) "
                f"SELECT k.t AS time, {cols} FROM k LEFT JOIN m ON m.t=k.t GROUP BY k.t ORDER BY k.t")


    auth_cols = ", ".join(f"COALESCE(SUM(CASE WHEN m.event='{e}' THEN m.count END),0) AS {e}"
                          for e in ("auth_started", "auth_succeeded", "auth_failed"))
    minute_desc = ("按北京时间分钟汇总、不含设备标识的计数。所选范围 ≤6 小时按 1 分钟、≤2 天按 5 分钟、"
                   "≤8 天按 10 分钟、≤32 天按 1 小时、更长按 1 天合并。数据随客户端约每 6 小时上传一次，最近几小时可能尚未到达。")
    panels.append(panel(
        "timeseries", "登录曲线", (0, y, 12, 9),
        [target(minute_sql(auth_cols, "event IN ('auth_started','auth_succeeded','auth_failed')"),
                [("time", "时间", "timestamp_epoch"), ("auth_started", "发起登录", "number"),
                 ("auth_succeeded", "登录成功", "number"), ("auth_failed", "登录失败", "number")], "timeseries")],
        minute_desc, ts_defaults(fill=10),
        [color_override("发起登录", C[0]), color_override("登录成功", C[2]), color_override("登录失败", CRIT)],
        TS_OPTS))
    fcols = ", ".join(f"COALESCE(SUM(CASE WHEN m.feature='{k}' THEN m.count END),0) AS {k}" for k, _ in TOP)
    panels.append(panel(
        "timeseries", "功能使用曲线", (12, y, 12, 9),
        [target(minute_sql(fcols + f", COALESCE(SUM(CASE WHEN m.feature NOT IN ({other}) THEN m.count END),0) AS other",
                           "event='feature_loaded'"),
                [("time", "时间", "timestamp_epoch")] + [(k, v, "number") for k, v in TOP] + [("other", "其他", "number")],
                "timeseries")],
        minute_desc + " 按功能堆叠。", ts_defaults(stack=True, fill=40),
        [color_override(v, C[i]) for i, (_, v) in enumerate(TOP)] + [color_override("其他", MUTED)],
        TS_OPTS))
    y += 9
    WEEK = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    hcols = ", ".join(f"COALESCE(SUM(CASE WHEN h={i} THEN n END),0) AS h{i}" for i in range(24))
    wk = "CASE w " + " ".join(f"WHEN {i} THEN '{n}'" for i, n in enumerate(WEEK)) + " END"
    panels.append(panel(
        "table", "一周使用热力（功能加载次数）", (0, y, 24, 9),
        [target(f"WITH x AS (SELECT CAST(strftime('%w',minute_at) AS INTEGER) AS w, CAST(substr(minute_at,12,2) AS INTEGER) AS h, "
                f"count AS n FROM minute_counts WHERE event='feature_loaded' AND minute_at BETWEEN {MIN_FROM} AND {MIN_TO} AND {MFILT}), "
                f"wd(w) AS (VALUES (1),(2),(3),(4),(5),(6),(0)) "
                f"SELECT {wk} AS day, {hcols} FROM wd LEFT JOIN x USING(w) GROUP BY wd.w ORDER BY (wd.w+6)%7",
                [("day", "星期", "string")] + [(f"h{i}", f"{i}时", "number") for i in range(24)])],
        "所选时段内按星期和小时（北京时间）汇总的功能加载次数，颜色越亮越多，用来看一周里的使用高峰。",
        {"custom": {"align": "center", "cellOptions": {"type": "color-background", "mode": "basic"}, "inspect": False,
                    "minWidth": 36},
         "unit": "short", "decimals": 0, "min": 0, "noValue": "0",
         "color": {"mode": "continuous-blues"}},
        [{"matcher": {"id": "byType", "options": "string"},
          "properties": [{"id": "custom.cellOptions", "value": {"type": "auto"}}, {"id": "custom.width", "value": 56}]}],
        {"showHeader": True, "cellHeight": "sm", "footer": {"show": False}}))
    y += 9

    # ───────── 性能 ─────────
    panels.append(row("性能", y)); y += 1
    blabel = case("bucket", BUCKETS)
    perf_sql = (f"WITH b AS (SELECT bucket, metric, SUM(count) AS n FROM timing_days WHERE metric IN ('cold_start','first_content','auth') "
                f"AND {WHERE} GROUP BY bucket, metric), tot AS (SELECT metric, SUM(n) AS s FROM b GROUP BY metric), "
                f"k(bucket) AS (VALUES " + ",".join(f"('{k}')" for k, _ in BUCKETS) + ") "
                f"SELECT {blabel} AS bucket, "
                + ", ".join(f"COALESCE((SELECT CAST(n AS REAL)/s FROM b JOIN tot USING(metric) WHERE b.bucket=k.bucket AND metric='{m}'),0) AS {m}"
                            for m in ("cold_start", "first_content", "auth"))
                + f" FROM k ORDER BY {BUCKET_ORDER}")
    panels.append(panel(
        "barchart", "启动、首屏与登录耗时分布", (0, y, 12, 10),
        [target(perf_sql, [("bucket", "耗时", "string"), ("cold_start", "冷启动", "number"),
                           ("first_content", "首屏内容", "number"), ("auth", "登录", "number")])],
        "各耗时区间在该指标样本中的占比。柱子越集中在左侧越好。",
        {"unit": "percentunit", "decimals": 0, "min": 0, "color": {"mode": "palette-classic"},
         "custom": {"fillOpacity": 85, "lineWidth": 0, "axisBorderShow": False}},
        [color_override("冷启动", C[0]), color_override("首屏内容", C[2]), color_override("登录", C[6])],
        {"orientation": "vertical", "stacking": "none", "barWidth": 0.8, "groupWidth": 0.75,
         "showValue": "never", "xTickLabelRotation": 0,
         "legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
         "tooltip": {"mode": "multi", "sort": "none"}}))
    heat_cols = ", ".join(
        f"CAST(SUM(CASE WHEN bucket{' IN (' + chr(39) + 'lt_250' + chr(39) + ',' + chr(39) + 'lt_500' + chr(39) + ')' if k == 'lt_500' else '=' + chr(39) + k + chr(39)}"
        f" THEN count ELSE 0 END) AS REAL)/SUM(count) AS {k}" for k, _ in BUCKETS if k != "lt_250")
    heat_labels = [("lt_500", "<0.5s"), ("lt_1000", "0.5–1s"), ("lt_2000", "1–2s"), ("lt_5000", "2–5s"),
                   ("lt_10000", "5–10s"), ("ge_10000", "≥10s")]
    SEQ = ["#1a1a19", "#104281", "#1c5cab", "#2a78d6", "#5598e7", "#86b6ef"]
    panels.append(panel(
        "table", "功能加载耗时分布", (12, y, 12, 10),
        [target(f"SELECT {FEAT()} AS name, SUM(count) AS n, {heat_cols} FROM timing_days "
                f"WHERE metric='feature_load' AND {WHERE} GROUP BY feature ORDER BY n DESC",
                [("name", "功能", "string"), ("n", "样本", "number")] + [(k, v, "number") for k, v in heat_labels])],
        "每行是一个功能的加载耗时分桶占比，颜色越亮占比越高。",
        {"custom": {"align": "center", "cellOptions": {"type": "color-background", "mode": "basic"}, "inspect": False,
                    "minWidth": 56},
         "unit": "percentunit", "decimals": 0, "min": 0, "max": 1,
         "color": {"mode": "thresholds"},
         "thresholds": {"mode": "absolute", "steps": [
             {"color": SEQ[0], "value": None}, {"color": SEQ[1], "value": 0.01}, {"color": SEQ[2], "value": 0.15},
             {"color": SEQ[3], "value": 0.3}, {"color": SEQ[4], "value": 0.5}, {"color": SEQ[5], "value": 0.7}]}},
        [prop_override("功能", ("custom.cellOptions", {"type": "auto"}), ("custom.align", "left"), ("custom.width", 110)),
         prop_override("样本", ("custom.cellOptions", {"type": "auto"}), ("unit", "short"), ("custom.width", 70))],
        {"showHeader": True, "cellHeight": "sm", "footer": {"show": False}}))
    y += 10

    # ───────── 稳定性 ─────────
    panels.append(row("稳定性", y)); y += 1
    panels += [
        stat("错误次数", (0, y, 6, 4), f"SELECT COALESCE(SUM(count),0) AS n FROM error_days WHERE {WHERE}",
             [("n", "错误", "number")], None, "所选时段内上报的错误总次数，含登录失败、功能失败、界面错误提示和崩溃。",
             thresholds=[{"color": GOOD, "value": None}, {"color": WARN, "value": 1}, {"color": CRIT, "value": 50}]),
        stat("受影响设备", (6, y, 6, 4), f"SELECT COUNT(DISTINCT install_id) AS n FROM error_days WHERE {WHERE}",
             [("n", "设备", "number")], None, "所选时段内至少上报过一次错误的去重设备数。",
             thresholds=[{"color": GOOD, "value": None}, {"color": WARN, "value": 1}]),
        stat("崩溃", (12, y, 6, 4),
             f"SELECT COALESCE(SUM(count),0) AS n FROM error_days WHERE event='crash' AND {WHERE}",
             [("n", "崩溃", "number")], None, "所选时段内的崩溃次数。",
             thresholds=[{"color": GOOD, "value": None}, {"color": CRIT, "value": 1}]),
        stat("登录成功率", (18, y, 6, 4),
             f"SELECT CAST(SUM(CASE WHEN event='auth_succeeded' THEN count ELSE 0 END) AS REAL)/"
             f"NULLIF(SUM(CASE WHEN event='auth_started' THEN count ELSE 0 END),0) AS rate FROM counter_days WHERE {WHERE}",
             [("rate", "登录成功率", "number")], None, "登录成功次数 ÷ 发起登录次数。用户中途取消也会拉低该值。",
             unit="percentunit", decimals=1,
             thresholds=[{"color": CRIT, "value": None}, {"color": WARN, "value": 0.8}, {"color": GOOD, "value": 0.95}]),
    ]
    y += 4
    kcols = ", ".join(f"COALESCE(SUM(CASE WHEN e.error_kind='{k}' THEN e.count END),0) AS {k}" for k, _ in KIND)
    panels.append(panel(
        "timeseries", "每日错误（按类型）", (0, y, 10, 10),
        [target(f"{DAYS} SELECT {TS}, {kcols} FROM d LEFT JOIN error_days e ON e.day=d.day AND "
                f"{filt('e.')} GROUP BY d.day ORDER BY d.day",
                [("time", "时间", "timestamp_epoch")] + [(k, v, "number") for k, v in KIND], "timeseries")],
        "按错误类型堆叠的每日错误次数。",
        ts_defaults(draw="bars", stack=True),
        [color_override(v, C[i]) for i, (_, v) in enumerate(KIND)], TS_OPTS))
    EVT = case("event", [("auth_failed", "登录失败"), ("feature_failed", "功能失败"),
                         ("ui_error_shown", "界面报错"), ("crash", "崩溃")])
    panels.append(panel(
        "table", "错误明细", (10, y, 14, 10),
        [target(f"SELECT {EVT} AS event, {FEAT()} AS feature, "
                f"CASE route WHEN 'direct' THEN '直连' WHEN 'webvpn' THEN 'WebVPN' ELSE '—' END AS route, "
                f"{case('error_kind', KIND)} AS kind, error_code, "
                f"CASE WHEN retryable=1 THEN '可重试' ELSE '' END AS retry, SUM(count) AS n, "
                f"COUNT(DISTINCT install_id) AS devices FROM error_days WHERE {WHERE} "
                f"GROUP BY event, feature, route, error_kind, error_code, retryable ORDER BY n DESC LIMIT 100",
                [("event", "事件", "string"), ("feature", "功能", "string"), ("route", "线路", "string"),
                 ("kind", "类型", "string"), ("error_code", "错误码", "string"), ("retry", "重试", "string"),
                 ("n", "次数", "number"), ("devices", "设备", "number")])],
        "所选时段内按事件、功能、线路和错误码汇总，按次数降序，最多 100 行。",
        {"custom": {"align": "auto", "cellOptions": {"type": "auto"}, "inspect": False, "filterable": True},
         "decimals": 0, "unit": "short"},
        [prop_override("次数", ("custom.cellOptions", {"type": "gauge", "mode": "basic", "valueDisplayMode": "text"}),
                       ("color", {"mode": "fixed", "fixedColor": CRIT}), ("custom.width", 140)),
         prop_override("事件", ("custom.width", 90)), prop_override("线路", ("custom.width", 70)),
         prop_override("类型", ("custom.width", 60)), prop_override("重试", ("custom.width", 60)),
         prop_override("设备", ("custom.width", 60))],
        {"showHeader": True, "cellHeight": "sm", "footer": {"show": False}}))
    y += 10

    # ───────── 数据管道（折叠） ─────────
    pipe = []
    py_ = y + 1
    pipe.append(panel(
        "stat", "接收与汇总状态", (0, py_, 12, 7),
        [target("SELECT (SELECT COUNT(*) FROM batches WHERE date(received_at,'+8 hours')=" + TODAY + ") AS today, "
                "(SELECT COUNT(*) FROM batches WHERE received_at >= datetime('now','-7 days')) AS week, "
                "(SELECT COALESCE((SELECT last_success_day FROM job_state WHERE job='aggregate'),'尚未运行')) AS job, "
                "(SELECT COUNT(*) FROM erased_installs WHERE erased_at >= datetime('now','-30 days')) AS erased, "
                "(SELECT COALESCE(MIN(day),'—') FROM active_days) AS first_day",
                [("today", "今日接收批次", "number"), ("week", "近 7 天批次", "number"),
                 ("job", "汇总任务最后成功日", "string"), ("erased", "近 30 天删除数据", "number"),
                 ("first_day", "明细最早日期", "string")])],
        "服务端整体状态，不受平台与渠道筛选影响。汇总任务每天 03:00 运行，本面板不依赖其结果。",
        {"unit": "short", "decimals": 0, "color": {"mode": "fixed", "fixedColor": "text"}},
        options={"reduceOptions": {"calcs": ["lastNotNull"], "fields": "/.*/", "values": False},
                 "colorMode": "none", "graphMode": "none", "textMode": "value_and_name",
                 "justifyMode": "center", "orientation": "horizontal", "wideLayout": True,
                 "text": {"titleSize": 13, "valueSize": 20}}))
    pipe.append(panel(
        "text", "统计口径", (12, py_, 12, 7), [], "",
        options={"mode": "markdown", "content": (
            "- 日期一律按**北京时间**自然日划分。\n"
            "- 本面板直接查询明细表：活跃数据保留 13 个月，功能、错误与耗时明细保留 90 天，分钟级计数保留 30 天，超过的时段不会显示。\n- **使用时段**来自不含设备标识的分钟级计数，只能看次数，不能去重；需要客户端新版本发布后才有数据。\n"
            "- **活跃用户**按账号派生标识去重，未绑定账号的设备只计入活跃设备；**活跃设备**按安装标识去重，重装会产生新标识。\n"
            "- 只统计用户允许上传的数据；用户删除已上传数据后，其历史明细会从所有图表中消失。\n"
            "- 迟到批次会修订近期数据。查询失败时面板显示错误，不要当作 0。")}))
    panels.append(row("数据管道与口径", y, collapsed=True, panels=pipe))
    y += 1

    for p in panels:
        if p["type"] == "text":
            p.pop("datasource"); p.pop("targets")

    dash = {
        "uid": "ubaa-telemetry", "title": "UBAA 使用情况", "tags": ["ubaa", "telemetry"],
        "timezone": "Asia/Shanghai", "editable": True, "graphTooltip": 1, "fiscalYearStartMonth": 0,
        "liveNow": False, "refresh": "15m", "schemaVersion": 41, "version": 1,
        "time": {"from": "now-30d/d", "to": "now"},
        "timepicker": {"refresh_intervals": ["5m", "15m", "1h", "6h"]},
        "annotations": {"list": []}, "links": [],
        "templating": {"list": [
            {"name": "platform", "label": "平台", "type": "custom", "multi": True, "includeAll": True,
             "query": "Android : android, iOS : ios, HarmonyOS : ohos, macOS : macos, Windows : windows, Linux : linux",
             "current": {"text": ["All"], "value": ["$__all"]}, "options": [], "hide": 0},
            {"name": "channel", "label": "渠道", "type": "custom", "multi": True, "includeAll": True,
             "query": "GitHub : github, App Store : app_store, 华为应用市场 : app_gallery",
             "current": {"text": ["All"], "value": ["$__all"]}, "options": [], "hide": 0},
        ]},
        "panels": panels,
    }
    return dash


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--account-id', default=os.environ.get('UBAA_APP_SERVICE_ACCOUNT_ID'))
    parser.add_argument('--database-id', default=os.environ.get('UBAA_APP_SERVICE_D1_ID'))
    parser.add_argument('--output', type=Path, help='写入的文件；省略时输出到 stdout')
    args = parser.parse_args()
    try:
        dash = build(args.account_id, args.database_id)
    except ValueError as error:
        raise SystemExit(f'error: {error}；请在 .env 或参数中提供 Cloudflare 账号与 D1 数据库 ID')
    text = json.dumps(dash, ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding='utf-8')
        print(f'已生成看板：{args.output}')
    else:
        sys.stdout.write(text)


if __name__ == '__main__':
    main()
