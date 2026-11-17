#!/usr/bin/env python3
"""在线备份留言数据库，并保留最近 14 天的副本。"""
from datetime import datetime, timedelta
from pathlib import Path
import sqlite3

root = Path('/var/lib/ubaa-comments')
backups = root / 'backups'
backups.mkdir(mode=0o700, exist_ok=True)
now = datetime.now()
with sqlite3.connect(f'file:{root / "artalk.db"}?mode=ro', uri=True) as source:
    with sqlite3.connect(backups / f'{now:%Y-%m-%d}.db') as target:
        source.backup(target)
for backup in backups.glob('*.db'):
    if backup.stem < (now - timedelta(days=14)).strftime('%Y-%m-%d'):
        backup.unlink()
