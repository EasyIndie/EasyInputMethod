"""Exercise credential lifecycle with fixtures and mock tools, never real signing."""
import base64
import os
from pathlib import Path
import subprocess
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "ci-sign.sh"
with tempfile.TemporaryDirectory(prefix="lampyris-ci-sign-test-") as directory:
    root = Path(directory)
    env = dict(os.environ, RUNNER_TEMP=directory)
    for name in (
        "MACOS_CERTIFICATE_P12_BASE64", "MACOS_CERTIFICATE_PASSWORD",
        "MACOS_SIGNING_IDENTITY", "ASC_API_KEY_P8_BASE64",
        "ASC_API_KEY_P8", "ASC_API_KEY_ID", "ASC_API_ISSUER_ID",
    ):
        env.pop(name, None)
    # 先用 fixture app，避免依赖本机是否已构建 platforms/macos/build/Lampyris.app
    app = root / "Fixture.app"
    app.mkdir()
    result = subprocess.run(["bash", str(SCRIPT), "--app", str(app)], env=env, capture_output=True, text=True)
    assert result.returncode == 1 and "缺少 CI 配置" in result.stderr, result.stderr
    assert not (root / "lampyris-signing").exists()
    binary = root / "bin"
    binary.mkdir()
    fake = '''#!/usr/bin/env bash
set -eu
case "$(basename "$0")" in
security)
 if [ "$1" = list-keychains ]; then
   if [ "$#" = 3 ]; then echo '"/fixture/login.keychain-db"';
   else printf '%s\n' "$*" >> "$RUNNER_TEMP/search-list.log"; fi
 fi
 if [ "$1" = find-identity ] && [ "${MOCK_NO_IDENTITY:-0}" = 0 ]; then
   echo '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Fixture"'
 fi
 if [ "$1" = create-keychain ]; then touch "${!#}"; fi
 if [ "$1" = delete-keychain ]; then rm -f "${!#}"; fi;;
ditto) touch "${!#}";;
xcrun)
 if [ "$1" = notarytool ]; then
   case "$2" in
     submit)
       if [ "${MOCK_NOTARY_ERROR:-0}" = 1 ]; then exit 77; fi
       if [ "${MOCK_NOTARY_FAIL:-0}" = 1 ]; then printf '{\n  "id" : "mock",\n  "status" : "Invalid"\n}\n';
       else printf '{\n  "id" : "mock",\n  "status" : "Accepted"\n}\n'; fi;;
     log) printf '{"issues":[{"message":"fixture rejection"}]}\n';;
   esac
 fi;;
esac
'''
    for name in ("security", "codesign", "ditto", "xcrun", "spctl"):
        path = binary / name
        path.write_text(fake)
        path.chmod(0o700)
    fixture = base64.b64encode(b"fixture").decode()
    env.update(
        PATH=str(binary) + ":" + os.environ["PATH"],
        MACOS_CERTIFICATE_P12_BASE64=fixture, MACOS_CERTIFICATE_PASSWORD="fixture",
        MACOS_SIGNING_IDENTITY="Developer ID Application: Fixture",
        ASC_API_KEY_P8_BASE64=fixture, ASC_API_KEY_ID="fixture", ASC_API_ISSUER_ID="fixture",
    )
    for failure, expected in (("0", 0), ("1", 1)):
        result = subprocess.run(["bash", str(SCRIPT), "--app", str(app)],
            env=dict(env, MOCK_NOTARY_FAIL=failure), capture_output=True, text=True)
        assert result.returncode == expected, result.stderr
        if failure == "1":
            # Apple 判 Invalid 时必须把它自己的诊断打出来，否则只剩 stapler 报错。
            assert "公证未通过" in result.stderr, result.stderr
            assert "fixture rejection" in result.stderr, result.stderr
        assert not (root / "lampyris-signing").exists()
        assert (root / "search-list.log").read_text().splitlines()[-1] == "list-keychains -d user -s /fixture/login.keychain-db"
    result = subprocess.run(["bash", str(SCRIPT), "--app", str(app)],
        env=dict(env, MOCK_NO_IDENTITY="1"), capture_output=True, text=True)
    assert result.returncode == 1 and "找不到唯一有效签名身份" in result.stderr
    assert not (root / "lampyris-signing").exists()
    pem = "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----"
    result = subprocess.run(["bash", str(SCRIPT), "--app", str(app)],
        env=dict(env, ASC_API_KEY_P8=pem), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert not (root / "lampyris-signing").exists()
    installer = root / "Installer.app"
    installer.mkdir()
    dmg = root / "Fixture.dmg"
    dmg.write_bytes(b"fixture")
    result = subprocess.run(["bash", str(SCRIPT), "--app", str(app), "--installer", str(installer),
        "--uninstaller", str(installer), "--sign-only"], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    updater = root / "Updater.app"
    updater.mkdir()
    # ADR-295：更新程序与主应用共用同一次公证提交；附加 app 缺失时直接拒绝。
    result = subprocess.run(["bash", str(SCRIPT), "--app", str(app), "--also", str(updater)],
        env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    result = subprocess.run(["bash", str(SCRIPT), "--app", str(app), "--also", str(root / "Missing.app")],
        env=env, capture_output=True, text=True)
    assert result.returncode == 1 and "附加 app 不存在" in result.stderr, result.stderr
    result = subprocess.run(["bash", str(SCRIPT), "--dmg", str(dmg)], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    subprocess.run(["bash", str(SCRIPT), "--cleanup"], env=env, check=True)
print("签名脚本模拟验证通过：缺失配置、成功、失败、DMG/安装器模式及清理；未访问真实凭据或Apple")


def _ci_sign_blocks():
    """按工作流取出每个真正执行 ci-sign.sh 的步骤前 20 行（含 env 块）。"""
    workflows = Path(__file__).resolve().parents[3] / ".github/workflows"
    for workflow in sorted(workflows.glob("*.yml")):
        lines = workflow.read_text().splitlines()
        for index, line in enumerate(lines):
            if "ci-sign.sh" not in line or "--cleanup" in line:
                continue
            yield workflow.name, "\n".join(lines[max(0, index - 20):index])


def test_workflows_pass_every_credential_to_ci_sign():
    """工作流喂给 ci-sign.sh 的 env 要给全 7 个变量，且 secret/var 名对得上。

    2026-11-23 把 secrets.APPLE_ASC_ISSUER_ID 误写成 APPLE_ASC_API_ISSUER_ID，
    release 在签名步骤直接失败（缺 ASC_API_ISSUER_ID）；光检查键名存在拦不住。
    """
    expected = {
        "MACOS_CERTIFICATE_P12_BASE64": "secrets.APPLE_CERTIFICATE_P12_BASE64",
        "MACOS_CERTIFICATE_PASSWORD": "secrets.APPLE_CERTIFICATE_P12_PASSWORD",
        "MACOS_SIGNING_IDENTITY": "vars.MACOS_SIGNING_IDENTITY",
        "ASC_API_KEY_P8": "secrets.APPLE_ASC_API_KEY",
        "ASC_API_KEY_ID": "secrets.APPLE_ASC_API_KEY_ID",
        "ASC_API_ISSUER_ID": "secrets.APPLE_ASC_ISSUER_ID",
    }
    checked = 0
    for name, block in _ci_sign_blocks():
        for key, reference in expected.items():
            assert f"{key}: ${{{{ {reference} }}}}" in block, (
                f"{name} 的 ci-sign 步骤里 {key} 必须绑定 {reference}")
        checked += 1
    assert checked >= 5, f"没找到足够的 ci-sign.sh 调用（找到 {checked} 处）"


test_workflows_pass_every_credential_to_ci_sign()
print("PASS test-ci-sign")
