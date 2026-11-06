"""验收只依赖系统自带应用（报告234）。

用户机器不一定装了 Chrome / Xcode / VS Code / 微信；把这些当成必需客户端会让验收
在干净系统上必然失败。规则：`open -a <App>` 里的非系统自带应用，必须在本文件里
先用 `has_app` 判断（装了就测、没装 SKIP），并且不能写死版本路径。
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
PROBE_DIR = ROOT / 'tools/macos-probe'

# macOS 每台机器都有的、可以作为门禁的应用。
SYSTEM_DEFAULT = {
    'TextEdit', 'Safari', 'Terminal', 'Finder', 'System Settings', 'System Preferences',
}

# 这些是被明确排除/降级的"用户自己装"的应用（出现在验收脚本里只允许作为 optional）。
OPEN_RE = re.compile(r'open\s+-n?a\s+"?([^"\s]+)"?')
GUARD_RE = re.compile(r'has_app\s+"?([^";\s)]+)"?')
HARDCODED_VERSION_PATH = re.compile(r'/Applications/[A-Za-z0-9 ._-]*-[0-9]+\.[0-9]+[^/]*\.app')


def code_only(text: str) -> str:
    """去掉注释行：注释里提到历史路径不算违规。"""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


class AcceptancePortabilityTests(unittest.TestCase):
    def test_non_default_apps_are_guarded(self):
        problems = []
        for path in sorted(PROBE_DIR.glob('*.sh')):
            text = code_only(path.read_text(encoding='utf-8'))
            guarded = set(GUARD_RE.findall(text))
            for app in OPEN_RE.findall(text):
                if app in SYSTEM_DEFAULT or app.startswith('/'):
                    continue
                if app not in guarded:
                    problems.append(f'{path.name}: 直接打开非系统自带应用 {app}，但没用 has_app 判断')
        self.assertEqual(problems, [], '验收不能假定用户装了非系统自带应用：\n' + '\n'.join(problems))

    def test_no_hardcoded_versioned_app_paths(self):
        problems = []
        for path in sorted(PROBE_DIR.glob('*.sh')):
            text = code_only(path.read_text(encoding='utf-8'))
            for hit in HARDCODED_VERSION_PATH.findall(text):
                problems.append(f'{path.name}: 写死了版本化应用路径 {hit}（用 `open -a <Name>`）')
        self.assertEqual(problems, [], '\n'.join(problems))

    def test_matrix_marks_required_versus_optional(self):
        text = (PROBE_DIR / 'client-matrix.sh').read_text(encoding='utf-8')
        self.assertIn('required_json', text, '矩阵必须区分必需/可选客户端')
        self.assertIn('"required":false', text, '可选客户端必须显式标记 required:false')
        # 必需集合只允许系统自带应用
        verdict = (PROBE_DIR / 'client-matrix-verdict.py').read_text(encoding='utf-8')
        self.assertIn('required', verdict, '判定脚本必须读取 required 字段')

    def test_checklists_do_not_require_third_party_apps(self):
        """清单里出现非系统自带应用时，必须显式写成可选/已移除，不能当必做。"""
        markers = ('可选', '移除', '不再', 'SKIP', '非系统自带')
        for name in ('docs/tasks/T-ITER-22.md', 'docs/tasks/T-ITER-22-coverage.md',
                     'docs/reviews/234-1.1.0-walkthrough.md'):
            text = (ROOT / name).read_text(encoding='utf-8')
            for line in text.splitlines():
                if 'VS Code' in line or 'Visual Studio' in line or '微信' in line:
                    self.assertTrue(any(marker in line for marker in markers),
                                    f'{name}: 把非系统自带应用当成必做 → {line.strip()}')


if __name__ == '__main__':
    unittest.main()
