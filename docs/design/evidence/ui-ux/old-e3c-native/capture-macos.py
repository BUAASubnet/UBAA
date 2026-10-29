"""历史 E3c 检查点采集器；通过参数指定本轮目录与窗口，不依赖个人工具。"""
from pathlib import Path
import argparse
import datetime
import json
import re
import struct
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--checkpoint-dir', required=True, type=Path)
parser.add_argument('--evidence-dir', required=True, type=Path)
parser.add_argument('--window-id', required=True, type=int)
args = parser.parse_args()
repo = next(parent for parent in Path(__file__).resolve().parents if (parent / 'justfile').is_file())
out = args.evidence_dir
if not out.is_absolute() or out.resolve().is_relative_to(repo):
    parser.error('--evidence-dir 必须是仓库外的新私有绝对目录')
if args.window_id <= 0:
    parser.error('--window-id 必须为本轮原生窗口的正整数 ID')
out.mkdir(mode=0o700, parents=True, exist_ok=False)
marker = args.checkpoint_dir / 'pending'
limit = time.monotonic() + 240
names = []
while len(names) < 5 and time.monotonic() < limit:
    if not marker.exists():
        time.sleep(.1)
        continue
    name = marker.read_text().strip()
    if not re.fullmatch(r'dark-normal-[a-z-]+', name):
        raise RuntimeError('不是本批合成检查点')
    if name in names:
        raise RuntimeError('拒绝覆盖检查点')
    image = out / (name + '.png')
    subprocess.run(['screencapture', '-x', '-l', str(args.window_id), str(image)], check=True)
    header = image.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b'\x89PNG\r\n\x1a\n':
        raise RuntimeError('原生截图不是 PNG')
    width, height = struct.unpack('>II', header[16:24])
    record = {'name': name, 'backend': 'synthetic-schedule-navigation', 'platform': 'macos',
              'sourceSha': '2610d316+E3c-r3-window', 'windowId': args.window_id,
              'physicalSize': [width, height], 'viewportSource': 'native-window-unmodified',
              'captureMethod': 'Flutter 原生测试检查点与系统截窗',
              'dateUtc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    (out / (name + '.json')).write_text(json.dumps(record, ensure_ascii=False, indent=2))
    names.append(name)
    marker.unlink()
    print('已截取 ' + name, flush=True)
if len(names) != 5:
    raise RuntimeError('检查点未完整完成')
(out / 'manifest.json').write_text(json.dumps(
    {'savedScreenshots': names, 'acceptance': '需要原生测试退出 0 及逐图复核'},
    ensure_ascii=False, indent=2))
