CREATE TABLE minute_counts (
  minute_at TEXT NOT NULL,
  event TEXT NOT NULL,
  feature TEXT NOT NULL,
  result TEXT NOT NULL,
  platform TEXT NOT NULL,
  channel TEXT NOT NULL,
  count INTEGER NOT NULL,
  PRIMARY KEY (minute_at, event, feature, result, platform, channel)
);
