#!/usr/bin/env python3
"""Shared guards for installed real-client probes (self-contained subset).

Safari/Chrome/VS Code probes were removed in 2026-11-14; only TextEdit and Terminal
remain as system-built-in clients. These helpers are intentionally generic so a
probe can be deleted without taking its guards with it.
"""
import hashlib
import subprocess


def run(arguments):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=15)


def require_ui_scripting():
    result = run(['/usr/bin/osascript', '-e', 'with timeout of 5 seconds',
                  '-e', 'tell application "System Events" to get UI elements enabled',
                  '-e', 'end timeout'])
    if result.stdout.strip() != 'true':
        raise RuntimeError('当前osascript执行链UI脚本不可用；未创建文档或切换输入源')


def stamp(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
