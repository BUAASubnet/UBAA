#!/usr/bin/env python3
"""顺序运行显式 HTTP 和 Bridge 联调，不接入 CI。"""

import subprocess
import sys

sys.dont_write_bytecode = True
import bridge_e2e
import http_e2e


if __name__ == "__main__":
    try:
        http_e2e.prepare()
        http_e2e.main()
        bridge_e2e.main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from None
