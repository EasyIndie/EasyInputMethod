#!/usr/bin/env python3
"""让机器睡下并等到唤醒：用「进程被挂起导致时钟跳变」判定真实睡着了、又被唤醒（报告204）。"""
import subprocess
import sys
import time

window = int(sys.argv[1]) if len(sys.argv) > 1 else 300
print("sleep_request", time.strftime("%FT%TZ", time.gmtime()), flush=True)
subprocess.run(["pmset", "sleepnow"], check=False, capture_output=True)
started = time.time()
previous = started
for _ in range(window):
    time.sleep(1)
    now = time.time()
    if now - previous > 5:
        print("wake gap=%.1fs at %s" % (now - previous, time.strftime("%FT%TZ", time.gmtime(now))), flush=True)
        raise SystemExit(0)
    previous = now
print("no_sleep_detected after %ds" % window, flush=True)
raise SystemExit(1)
