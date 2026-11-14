"""验收自闭环：不再依赖 Safari / Chrome / Xcode / VS Code / 微信（2026-11-14）。

用户要求收敛外部依赖：自动化验收只允许系统自带 TextEdit 与自建 imetype 测试窗口；
第三方客户端探针、fixture 与矩阵脚本已删除，且不得回流。
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
PROBE_DIR = ROOT / 'tools/macos-probe'
TEST_DIR = ROOT / 'platforms/macos/tests'

# 明确移除的自动化客户端（出现即失败；历史文档/报告不计）。
REMOVED = ('Safari', 'Google Chrome', 'Chrome', 'Xcode', 'VS Code', 'VSCode', '微信', 'WeChat')
OPEN_RE = re.compile(r'open\s+-n?a\s+"?([^"\s]+)"?')
CLIENT_MATRIX_RE = re.compile(r'client-matrix')


def code_only(text: str) -> str:
    """去掉注释行：注释里提到历史路径不算违规。"""
    return "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))


class AcceptancePortabilityTests(unittest.TestCase):
    def test_probe_scripts_do_not_open_removed_apps(self):
        problems = []
        for path in sorted(PROBE_DIR.glob('*.sh')):
            text = code_only(path.read_text(encoding='utf-8'))
            for app in OPEN_RE.findall(text):
                if app in REMOVED or any(name in app for name in REMOVED):
                    problems.append(f'{path.name}: 打开了已移除的客户端 {app}')
            for name in REMOVED:
                if re.search(rf'open\s+-n?a\s+"?[^"\n]*{re.escape(name)}', text):
                    problems.append(f'{path.name}: 仍引用已移除的客户端 {name}')
        self.assertEqual(problems, [], '验收不得再依赖第三方客户端：\n' + '\n'.join(problems))

    def test_client_matrix_is_gone(self):
        self.assertFalse((PROBE_DIR / 'client-matrix.sh').exists(), 'client-matrix.sh 应已删除')
        self.assertFalse((PROBE_DIR / 'client-matrix-verdict.py').exists(), 'client-matrix-verdict.py 应已删除')
        auto = (PROBE_DIR / 'acceptance-auto.sh').read_text(encoding='utf-8')
        self.assertNotRegex(code_only(auto), CLIENT_MATRIX_RE, 'acceptance-auto 不应再调用客户端矩阵')

    def test_third_party_probe_files_are_gone(self):
        for pattern in ('*safari*', '*chrome*', '*vscode*', '*input-apps*'):
            self.assertEqual(list(TEST_DIR.glob(pattern)), [], f'第三方客户端探针应已删除：{pattern}')

    def test_checklists_mark_third_party_apps_removed(self):
        """清单提到第三方客户端时，必须显式写成已移除/非依赖，不能当必做。"""
        markers = ('移除', '不再', '非依赖', '已删', '不依赖')
        for name in ('docs/tasks/T-ITER-22.md', 'docs/tasks/T-ITER-22-coverage.md'):
            text = (ROOT / name).read_text(encoding='utf-8')
            for line in text.splitlines():
                if any(app in line for app in ('Safari', 'Chrome', 'Xcode', 'VS Code', '微信')):
                    self.assertTrue(any(marker in line for marker in markers),
                                    f'{name}: 第三方客户端仍被当成必做 → {line.strip()}')


if __name__ == '__main__':
    unittest.main()
