#!/usr/bin/env python3
"""Bind a formal candidate to a separate account; never perform desktop actions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import stat
import sys


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def private_path(path, uid, directory):
    value = path.lstat()
    if stat.S_ISLNK(value.st_mode) or (directory and not stat.S_ISDIR(value.st_mode)) or (not directory and not stat.S_ISREG(value.st_mode)):
        raise ValueError('数据路径类型或符号链接不符：' + str(path))
    if value.st_uid != uid or value.st_mode & 0o022:
        raise ValueError('数据路径归属或可写权限不符：' + str(path))
    if not directory and value.st_nlink != 1:
        raise ValueError('数据文件存在硬链接：' + str(path))
    return value


def account():
    entry = pwd.getpwuid(os.geteuid())
    if os.getuid() != os.geteuid():
        raise ValueError('拒绝真实/有效UID不同的执行链')
    return entry.pw_uid, Path(entry.pw_dir)


def binding(candidate, commit):
    if not re.fullmatch('[0-9a-f]{40}', commit):
        raise ValueError('候选commit须为40位小写SHA')
    uid, home = account()
    if uid == 0 or home.resolve() != home:
        raise ValueError('原操作者账号或home不符')
    if candidate.is_symlink() or not candidate.is_file():
        raise ValueError('候选归档须为普通文件')
    return {'schema': 1, 'scope': 'separate-account-preflight',
            'operator_uid': uid, 'operator_home': str(home),
            'candidate_sha256': digest(candidate), 'candidate_commit': commit}


def verify(plan, candidate):
    if plan.get('schema') != 1 or plan.get('scope') != 'separate-account-preflight':
        raise ValueError('账号绑定单格式不符')
    operator = plan.get('operator_uid')
    if type(operator) is not int or operator <= 0:
        raise ValueError('原操作者UID无效')
    for key, length in [('candidate_sha256', 64), ('candidate_commit', 40)]:
        if not isinstance(plan.get(key), str) or not re.fullmatch('[0-9a-f]{' + str(length) + '}', plan[key]):
            raise ValueError('候选身份无效：' + key)
    original = Path(plan.get('operator_home', ''))
    if not original.is_absolute() or '..' in original.parts or original == Path('/'):
        raise ValueError('原操作者home无效')
    uid, home = account()
    if uid in (0, operator):
        raise ValueError('必须在不同于原操作者的非root测试账号运行；未允许后续动作')
    if not home.is_absolute() or home.resolve() != home or home == original or original in home.parents or home in original.parents:
        raise ValueError('测试home未与原账号分离')
    if os.environ.get('HOME') != str(home):
        raise ValueError('HOME与账号数据库不符，不接受环境变量伪隔离')
    # Check every existing component, including missing leaves whose parents may be linked.
    private_path(home, uid, True)
    paths = [home / 'Library', home / 'Library/Application Support', home / 'Library/Application Support/Lampyris']
    missing = False
    for path in paths:
        try:
            if missing:
                raise FileNotFoundError()
            private_path(path, uid, True)
        except FileNotFoundError:
            missing = True
    data = paths[-1]
    files = {}
    for name in ['config.toml', 'user-dictionary.tsv']:
        path = data / name
        if missing:
            files[name] = None
            continue
        try:
            private_path(path, uid, False)
            files[name] = digest(path)
        except FileNotFoundError:
            files[name] = None
    if candidate.is_symlink() or not candidate.is_file() or digest(candidate) != plan['candidate_sha256']:
        raise ValueError('候选归档缺失或摘要漂移')
    return {'status': 'PROFILE_READY', 'scope': 'account-data-paths-only',
            'uid': uid, 'home': str(home), 'data_directory': str(data),
            'data_before': files, 'candidate_sha256': plan['candidate_sha256'],
            'candidate_commit': plan['candidate_commit'], 'desktop_actions_executed': False,
            'formal_result': 'BLOCKED',
            'remaining': ['GUI登录账号及宿主身份', '签名公证/安装副本摘要', '当前空闲及权限', '逐动作焦点/所有权', '真实输入与恢复证据']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['bind', 'check'])
    parser.add_argument('--candidate', type=Path, required=True, help='同一最终候选归档，检查只读摘要')
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--commit', help='bind必需；不是从用户目录推断')
    args = parser.parse_args()
    try:
        if args.action == 'bind':
            plan = binding(args.candidate, args.commit or '')
            with args.plan.open('x', encoding='utf-8') as stream:
                os.fchmod(stream.fileno(), 0o600)
                json.dump(plan, stream, ensure_ascii=False, indent=2)
            print('BOUND：仅创建账号/候选绑定单，尚未验收')
        else:
            result = verify(json.loads(args.plan.read_text()), args.candidate)
            print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(json.dumps({'status': 'BLOCKED', 'formal_result': 'BLOCKED', 'desktop_actions_executed': False, 'reason': str(error)}, ensure_ascii=False))
        return 3


if __name__ == '__main__':
    sys.exit(main())
