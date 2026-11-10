CREATE TABLE batches (
  batch_id TEXT PRIMARY KEY,
  nonce TEXT NOT NULL,
  received_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE erased_installs (
  install_id TEXT PRIMARY KEY,
  erased_at TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE active_days (
  day TEXT NOT NULL,
  install_id TEXT NOT NULL,
  user_key TEXT NOT NULL,
  app_version TEXT NOT NULL,
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  cohort_type TEXT NOT NULL,
  cohort_year INTEGER NOT NULL,
  surface_mask INTEGER NOT NULL,
  PRIMARY KEY (day, install_id, user_key, app_version)
) WITHOUT ROWID;

CREATE TABLE counter_days (
  day TEXT NOT NULL,
  install_id TEXT NOT NULL,
  app_version TEXT NOT NULL,
  event TEXT NOT NULL,
  feature TEXT NOT NULL,
  route TEXT NOT NULL,
  result TEXT NOT NULL,
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (day, install_id, app_version, event, feature, route, result)
) WITHOUT ROWID;

CREATE TABLE error_days (
  day TEXT NOT NULL,
  install_id TEXT NOT NULL,
  app_version TEXT NOT NULL,
  event TEXT NOT NULL,
  feature TEXT NOT NULL,
  route TEXT NOT NULL,
  error_code TEXT NOT NULL,
  error_kind TEXT NOT NULL,
  retryable INTEGER NOT NULL,
  source TEXT NOT NULL,
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (day, install_id, app_version, event, feature, route, error_code, error_kind, retryable, source)
) WITHOUT ROWID;

CREATE TABLE timing_days (
  day TEXT NOT NULL,
  install_id TEXT NOT NULL,
  app_version TEXT NOT NULL,
  metric TEXT NOT NULL,
  feature TEXT NOT NULL,
  route TEXT NOT NULL,
  bucket TEXT NOT NULL,
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (day, install_id, app_version, metric, feature, route, bucket)
) WITHOUT ROWID;

CREATE TABLE active_daily (
  day TEXT NOT NULL,
  dimension TEXT NOT NULL,
  value TEXT NOT NULL,
  users INTEGER NOT NULL,
  devices INTEGER NOT NULL,
  PRIMARY KEY (day, dimension, value)
) WITHOUT ROWID;

CREATE TABLE active_monthly (
  month TEXT NOT NULL,
  dimension TEXT NOT NULL,
  value TEXT NOT NULL,
  users INTEGER NOT NULL,
  devices INTEGER NOT NULL,
  PRIMARY KEY (month, dimension, value)
) WITHOUT ROWID;

CREATE TABLE counter_daily (
  day TEXT NOT NULL,
  app_version TEXT NOT NULL,
  event TEXT NOT NULL,
  feature TEXT NOT NULL,
  route TEXT NOT NULL,
  result TEXT NOT NULL,
  count INTEGER NOT NULL,
  devices INTEGER NOT NULL,
  PRIMARY KEY (day, app_version, event, feature, route, result)
) WITHOUT ROWID;

CREATE TABLE error_daily (
  day TEXT NOT NULL,
  app_version TEXT NOT NULL,
  event TEXT NOT NULL,
  feature TEXT NOT NULL,
  route TEXT NOT NULL,
  error_code TEXT NOT NULL,
  error_kind TEXT NOT NULL,
  retryable INTEGER NOT NULL,
  source TEXT NOT NULL,
  count INTEGER NOT NULL,
  devices INTEGER NOT NULL,
  PRIMARY KEY (day, app_version, event, feature, route, error_code, error_kind, retryable, source)
) WITHOUT ROWID;

CREATE TABLE timing_daily (
  day TEXT NOT NULL,
  app_version TEXT NOT NULL,
  metric TEXT NOT NULL,
  feature TEXT NOT NULL,
  route TEXT NOT NULL,
  bucket TEXT NOT NULL,
  count INTEGER NOT NULL,
  devices INTEGER NOT NULL,
  PRIMARY KEY (day, app_version, metric, feature, route, bucket)
) WITHOUT ROWID;

CREATE TABLE job_state (
  job TEXT PRIMARY KEY,
  last_success_day TEXT NOT NULL
) WITHOUT ROWID;

-- 日期查询复用以 day 开头的主键；删除按安装 ID 定位明细。
CREATE INDEX active_days_install ON active_days (install_id);
CREATE INDEX counter_days_install ON counter_days (install_id);
CREATE INDEX error_days_install ON error_days (install_id);
CREATE INDEX timing_days_install ON timing_days (install_id);
CREATE INDEX batches_received ON batches (received_at);
CREATE INDEX erased_installs_time ON erased_installs (erased_at);
