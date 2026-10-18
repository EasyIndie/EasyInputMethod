#!/usr/bin/env python3
"""Persist local component acceptance, without desktop events or installed IMK access."""
import argparse
from datetime import datetime, timezone
import hashlib
import html
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PRODUCT_PATHS = ['crates', 'data/generated', 'data/learning', 'platforms/macos/Sources', 'platforms/macos/Preview']
SUITES = {
    'menu-view': ('test-input-menu.py', ['menu-view.' + name for name in ['state', 'structure', 'cycle', 'copy']]),
    'menu': ('test-preview-menu.py', ['menu.' + name for name in ['parent-cycle', 'cycle-order', 'same-mode', 'change-mode', 'states', 'external-settings', 'shortcut-refresh', 'shortcut-event', 'write-failure', 'recovery', 'routes', 'dictionary']]),
    'settings': ('test-settings-presentation.py', ['settings.' + name for name in ['groups', 'count', 'shortcuts', 'shortcut-rebind', 'descriptions', 'appearances', 'theme', 'failure', 'dictionary-session', 'reopen']]),
    'candidate': ('test-candidate-presentation.py', ['candidate.' + name for name in ['body', 'ax-selection', 'paging', 'page-centres', 'warning', 'long', 'glyph-display', 'glyph-commit', 'stale', 'padding', 'status', 'hud', 'hud-position']]),
    'tools': ('test-tools-presentation.py', ['tools.form.' + theme + '.' + action for theme in ['light', 'dark'] for action in ['add', 'delete']] + ['tools.' + name + '.' + theme for name in ['about', 'link-fallback', 'link-success'] for theme in ['light', 'dark']] + ['tools.hidden-parent', 'tools.clipboard']),
    'learning': ('test-wubi-learning.py', ['learning.' + name for name in ['facts', 'defaults', 'display', 'hidden', 'shortcut', 'width-shortcut', 'conflict', 'body-width', 'stale', 'stale-chord', 'contrast.light', 'contrast.dark', 'scroll', 'viewport']]),
}

REQUIRED_ARTIFACTS = {
    'menu-view': [],
    'menu': [],
    'settings': ['pane-0-light.png', 'pane-0-dark.png', 'pane-1-dark.png', 'minimum-0-light.png', 'description-baselines.json'],
    'candidate': ['light.png', 'dark.png', 'pinyin-a-missing-glyph-light.png', 'pinyin-a-missing-glyph-dark.png'],
    'tools': ['about-light.png', 'about-dark.png', 'add-light.png', 'delete-dark.png', 'feedback-failure-dark.png'],
    'learning': ['你-light.png', '你-dark.png', 'long-expanded-light.png', 'matched-learning-light.png', 'feedback-tr-light.png'],
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT).decode().strip()


def source_identity():
    paths = subprocess.check_output(['git', 'ls-files', '-z', '--', *PRODUCT_PATHS], cwd=ROOT).split(b'\0')
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z', '--', *PRODUCT_PATHS], cwd=ROOT).split(b'\0')
    paths = sorted(set(p.decode() for p in paths + untracked if p))
    digest = hashlib.sha256()
    for name in paths:
        path = ROOT / name
        digest.update(name.encode() + b'\0' + (sha(path) if path.is_file() else 'MISSING').encode() + b'\0')
    modified = subprocess.check_output(['git', 'diff', '--name-only', '-z', 'HEAD', '--', *PRODUCT_PATHS], cwd=ROOT).split(b'\0')
    return {'head_commit': git('rev-parse', 'HEAD'),
            'product_revision': git('log', '-1', '--format=%H', '--', *PRODUCT_PATHS),
            'product_sha256': digest.hexdigest(),
            'cargo_lock_sha256': sha(ROOT / 'Cargo.lock'),
            'toolchain_sha256': sha(ROOT / 'rust-toolchain.toml'),
            'modified_product_files': sorted(set(p.decode() for p in modified + untracked if p))}


def harness_identity():
    names = ['run-local-acceptance.py', 'local_acceptance_support.py', 'LocalAcceptanceEvidence.swift',
             'input-menu.swift', 'preview-menu.swift', 'settings-presentation.swift', 'candidate-presentation.swift',
             'tools-presentation.swift', 'wubi-learning.swift'] + [entry[0] for entry in SUITES.values()]
    return {name: sha(HERE / name) for name in names}


def observe(path, required):
    data = json.loads(path.read_text())
    if data.get('schema') != 1 or not isinstance(data.get('cases'), list):
        raise ValueError('观测schema或cases无效')
    cases = data['cases']
    ids = [c.get('id') for c in cases if isinstance(c, dict)]
    if len(ids) != len(cases) or len(ids) != len(set(ids)) or set(ids) != set(required):
        raise ValueError('必测场景缺失/重复/未知: ' + str(sorted(set(required) - set(ids))))
    for case in cases:
        if case.get('status') != 'PASS' or case.get('scope') != 'native-offscreen-components':
            raise ValueError('观测不是已通过的本地组件检查')
        if not case.get('expected') or 'actual' not in case or not case.get('observed_at'):
            raise ValueError('观测缺少预期/实测值/时间')
    return cases


def formal_gaps():
    spec = importlib.util.spec_from_file_location('formal_acceptance', HERE / 'acceptance-results.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return [{'id': name, 'status': 'BLOCKED',
             'reason': '本轮仅本地组件自动化；该项须单独的实际场景/正式候选证据，未补填历史PASS'}
            for name in module.REQUIRED]


def manifest(directory):
    return [{'path': str(p.relative_to(directory)), 'bytes': p.stat().st_size, 'sha256': sha(p)}
            for p in sorted(directory.rglob('*')) if p.is_file() and p.name not in ['report.json', 'report.md', 'report.html']]


def check(directory):
    report = json.loads((directory / 'report.json').read_text())
    if report.get('schema') != 1 or report.get('scope') != 'native-offscreen-components':
        raise ValueError('不是本地组件验收报告')
    if report.get('mvp_result') != 'BLOCKED' or report.get('formal_cases') != formal_gaps():
        raise ValueError('本地报告不能改变正式MVP门禁')
    if report.get('source_before') != report.get('source_after') or report.get('harness_before') != report.get('harness_after'):
        raise ValueError('运行前后源码或测试脚本变化')
    source = report['source_before']
    for field, length in [('head_commit', 40), ('product_revision', 40), ('product_sha256', 64), ('cargo_lock_sha256', 64), ('toolchain_sha256', 64)]:
        value = source.get(field)
        if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{' + str(length) + '}', value):
            raise ValueError('源码身份字段无效: ' + field)
    harness = report['harness_before']
    if not isinstance(harness, dict) or not harness or any(not isinstance(v, str) or not re.fullmatch('[0-9a-f]{64}', v) for v in harness.values()):
        raise ValueError('测试脚本身份缺失')
    for name, digest in harness.items():
        path = directory / 'harness' / name
        if Path(name).name != name or not path.is_file() or sha(path) != digest:
            raise ValueError('测试源码快照缺失或变化: ' + name)
    artifacts = report.get('artifacts', [])
    if not artifacts or len({a['path'] for a in artifacts}) != len(artifacts):
        raise ValueError('缺少或重复证据清单')
    base = directory.resolve()
    for item in artifacts:
        path = directory / item['path']
        if not path.resolve().is_relative_to(base) or path.is_symlink() or not path.is_file():
            raise ValueError('证据路径越界/缺失/符号链接: ' + item['path'])
        if path.stat().st_size != item['bytes'] or sha(path) != item['sha256']:
            raise ValueError('证据哈希不符: ' + item['path'])
    if artifacts != manifest(directory):
        raise ValueError('产物与清单不一致')
    jobs = report.get('suites', [])
    if len(jobs) != len(SUITES) or {j['id'] for j in jobs} != set(SUITES):
        raise ValueError('套件覆盖不完整')
    count = 0
    for job in jobs:
        key = job['id']
        if (job.get('status') != 'PASS' or job.get('exit') != 0 or job.get('script') != SUITES[key][0]
                or not isinstance(job.get('command'), list) or len(job['command']) != 2
                or Path(job['command'][1]).name != SUITES[key][0]):
            raise ValueError('套件未成功或命令不匹配: ' + key)
        cases = observe(directory / key / 'observations.json', SUITES[key][1])
        for name in ['run.log', 'observations.json', 'probe.json'] + REQUIRED_ARTIFACTS[key]:
            if not (directory / key / name).is_file():
                raise ValueError('场景所需产物缺失: ' + key + '/' + name)
        probe = json.loads((directory / key / 'probe.json').read_text())
        if (not isinstance(probe.get('bytes'), int) or probe['bytes'] <= 0
                or not re.fullmatch('[0-9a-f]{64}', probe.get('sha256', ''))
                or probe.get('cargo_lock_sha256') != source['cargo_lock_sha256']):
            raise ValueError('缺少编译探针身份: ' + key)
        if cases != job.get('cases'):
            raise ValueError('汇总与原始观测不符: ' + key)
        count += len(cases)
    if report.get('local_result') != 'PASS' or report.get('case_count') != count:
        raise ValueError('本地结果/场景数不一致')
    return count


def render(directory, report):
    intro = ('本地原生组件自动验收；不操作桌面，不等同已装IMK/物理键盘/VoiceOver/实际外链/整体MVP。'
             '未记录的历史手工操作没有补填PASS。')
    lines = ['# 本地自动验收记录', '', intro, '',
             f"本地结果：{report['local_result']}；MVP：BLOCKED；HEAD：{report['source_before']['head_commit']}", '',
             '| 场景 | 状态 | 预期 | 实测 |', '|---|---|---|---|']
    rows = []
    for job in report['suites']:
        for case in job.get('cases', []) + job.get('unobserved_cases', []):
            actual = json.dumps(case['actual'], ensure_ascii=False, sort_keys=True)
            lines.append('| ' + ' | '.join(str(v).replace('|', '\\|').replace('\n', ' ') for v in [case['id'], case['status'], case['expected'], actual]) + ' |')
            rows.append('<tr><td>' + html.escape(case['id']) + '</td><td>' + case['status'] + '</td><td>' + html.escape(case['expected']) + '</td><td><pre>' + html.escape(actual) + '</pre></td></tr>')
        if job.get('error'):
            lines.extend(['', job['id'] + '：' + job['error']])
    lines.extend(['', '## 原始证据', ''])
    images = []
    for item in report['artifacts']:
        name = item['path']
        lines.append('- [' + name + '](' + name + ') SHA-256 ' + item['sha256'])
        if name.endswith('.png'):
            images.append('<a href="' + html.escape(name, quote=True) + '"><img loading="lazy" src="' + html.escape(name, quote=True) + '" alt="' + html.escape(name, quote=True) + '"></a>')
    lines.extend(['', '## 正式MVP仍缺的证据', ''] + ['- BLOCKED ' + c['id'] + '：' + c['reason'] for c in report['formal_cases']])
    (directory / 'report.md').write_text('\n'.join(lines) + '\n')
    page = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>本地自动验收</title><style>body{font:15px system-ui;margin:28px;color:#222}table{border-collapse:collapse;width:100%}td,th{border:1px solid #bbb;padding:8px;text-align:left;vertical-align:top}pre{white-space:pre-wrap;overflow-wrap:anywhere;margin:0}img{max-width:340px;margin:8px;border:1px solid #bbb}code{overflow-wrap:anywhere}</style><h1>本地自动验收</h1><p>' + html.escape(intro) + '</p><p>本地：' + report['local_result'] + '；MVP：BLOCKED；场景数：' + str(report['case_count']) + '</p><p>源树：<code>' + report['source_before']['product_sha256'] + '</code></p><table><tr><th>场景</th><th>状态</th><th>预期</th><th>实测</th></tr>' + ''.join(rows) + '</table><h2>原生离屏截图</h2>' + ''.join(images) + '<h2>正式MVP仍缺的证据</h2><ul>' + ''.join('<li>BLOCKED ' + html.escape(c['id'] + '：' + c['reason']) + '</li>' for c in report['formal_cases']) + '</ul><p>逐文件SHA和命令见 report.json；可用 --check 重验原始证据。</p></html>'
    (directory / 'report.html').write_text(page)


def execute(command, env, stream, timeout=180):
    process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=stream,
                               stderr=subprocess.STDOUT, start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except BaseException:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
        raise


def run(directory):
    source = source_identity()
    harness = harness_identity()
    snapshots = directory / 'harness'
    snapshots.mkdir(mode=0o700)
    for name in harness:
        shutil.copyfile(HERE / name, snapshots / name)
    if source['modified_product_files']:
        for name in source['modified_product_files']:
            path = ROOT / name
            if path.is_file():
                target = directory / 'product-edits' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
    report = {'schema': 1, 'scope': 'native-offscreen-components', 'started_at': datetime.now(timezone.utc).isoformat(),
              'source_before': source, 'harness_before': harness, 'environment': {'system': platform.platform(), 'architecture': platform.machine(), 'macos': platform.mac_ver()[0], 'python': platform.python_version()},
              'local_result': 'BLOCKED', 'mvp_result': 'BLOCKED', 'formal_cases': formal_gaps(), 'suites': []}
    for name, (script, required) in SUITES.items():
        work = directory / name
        work.mkdir(mode=0o700)
        command = [sys.executable, str(HERE / script)]
        env = {**os.environ, 'LAMPYRIS_ACCEPTANCE_OUTPUT': str(work), 'CARGO_NET_OFFLINE': 'true', 'PYTHONDONTWRITEBYTECODE': '1'}
        job = {'id': name, 'script': script, 'command': command, 'status': 'BLOCKED', 'exit': None, 'cases': []}
        started = time.monotonic()
        with (work / 'run.log').open('w') as stream:
            try:
                if report.get('interrupted'):
                    raise KeyboardInterrupt()
                job['exit'] = execute(command, env, stream)
                if job['exit']:
                    job.update(status='FAIL', error='测试进程失败；详见run.log')
                else:
                    job['cases'] = observe(work / 'observations.json', required)
                    if not (work / 'probe.json').is_file():
                        raise ValueError('缺少编译探针身份')
                    job['status'] = 'PASS'
            except (OSError, ValueError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                job['error'] = str(error) or '本轮运行中断'
                if isinstance(error, KeyboardInterrupt):
                    report['interrupted'] = True
        if not job['cases'] and (work / 'observations.json').is_file():
            try:
                partial = json.loads((work / 'observations.json').read_text())['cases']
                job['cases'] = [c for c in partial if isinstance(c, dict) and c.get('id') in required]
            except (OSError, ValueError, KeyError, TypeError):
                pass
        recorded = {c['id'] for c in job['cases']}
        job['unobserved_cases'] = [{'id': case, 'status': 'BLOCKED', 'expected': '前置未通过或未记录该场景', 'actual': '见本套件run.log'} for case in required if case not in recorded]
        job['seconds'] = round(time.monotonic() - started, 3)
        report['suites'].append(job)
        print(job['status'] + ' ' + name + ' cases=' + str(len(job['cases'])), flush=True)
    report['source_after'] = source_identity()
    report['harness_after'] = harness_identity()
    report['artifacts'] = manifest(directory)
    report['case_count'] = sum(len(j['cases']) for j in report['suites'])
    stable = source == report['source_after'] and harness == report['harness_after']
    report['local_result'] = ('PASS' if stable and all(j['status'] == 'PASS' for j in report['suites'])
                              else 'FAIL' if any(j['status'] == 'FAIL' for j in report['suites']) else 'BLOCKED')
    report['completed_at'] = datetime.now(timezone.utc).isoformat()
    (directory / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    render(directory, report)
    try:
        count = check(directory)
        print(f'PASS local components: {count} recorded cases; MVP remains BLOCKED')
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('INCOMPLETE: ' + str(error))
        return 3 if report['local_result'] == 'BLOCKED' else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='新建的独立运行目录；已存在则拒绝覆盖')
    parser.add_argument('--check', type=Path, help='只核验已有报告与原始产物SHA，不执行测试')
    args = parser.parse_args()
    if args.check:
        try:
            print('PASS evidence verification: ' + str(check(args.check)) + ' cases; MVP remains BLOCKED')
            return 0
        except (OSError, ValueError, KeyError, TypeError) as error:
            print('INCOMPLETE: ' + str(error))
            return 2
    def interrupted(_signum, _frame):
        raise KeyboardInterrupt()
    signal.signal(signal.SIGTERM, interrupted)
    os.umask(0o077)
    if args.output:
        directory = args.output.resolve()
        directory.mkdir(parents=True, mode=0o700, exist_ok=False)
    else:
        parent = ROOT / 'platforms/macos/build/local-acceptance'
        parent.mkdir(parents=True, exist_ok=True)
        directory = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    print('EVIDENCE=' + str(directory), flush=True)
    return run(directory)


if __name__ == '__main__':
    sys.exit(main())
