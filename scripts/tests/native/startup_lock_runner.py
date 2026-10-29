#!/usr/bin/env python3
"""登记夹具只传入持锁程序；私有目录与独立子进程由应用创建。"""
import base64
from pathlib import Path
import subprocess
import sys


def run(command):
    script = Path(__file__).with_name('lock_holder.pl').read_bytes()
    encoded = base64.b64encode(script).decode('ascii')
    return subprocess.call([*command, f'--dart-define=UBAA_STARTUP_LOCK_HOLDER={encoded}'])


if __name__ == '__main__':
    raise SystemExit(run(sys.argv[1:]))
