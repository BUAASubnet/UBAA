-- 每个安装、日期、版本和错误维度保留最新的安全诊断样本。
CREATE TABLE error_samples (
  day TEXT NOT NULL,
  install_id TEXT NOT NULL,
  app_version TEXT NOT NULL,
  event TEXT NOT NULL,
  feature TEXT NOT NULL,
  route TEXT NOT NULL,
  error_code TEXT NOT NULL,
  source TEXT NOT NULL,
  diagnostic JSONB NOT NULL,
  PRIMARY KEY (day, install_id, app_version, event, feature, route, error_code, source)
);
CREATE INDEX error_samples_install ON error_samples (install_id);
