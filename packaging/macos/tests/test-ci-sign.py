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
    result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
    assert result.returncode == 1 and "缺少 CI 配置" in result.stderr
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
xcrun) if [ "$1" = notarytool ] && [ "${MOCK_NOTARY_FAIL:-0}" = 1 ]; then exit 77; fi;;
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
    for failure, expected in (("0", 0), ("1", 77)):
        result = subprocess.run(["bash", str(SCRIPT)],
            env=dict(env, MOCK_NOTARY_FAIL=failure), capture_output=True, text=True)
        assert result.returncode == expected, result.stderr
        assert not (root / "lampyris-signing").exists()
        assert (root / "search-list.log").read_text().splitlines()[-1] == "list-keychains -d user -s /fixture/login.keychain-db"
    result = subprocess.run(["bash", str(SCRIPT)],
        env=dict(env, MOCK_NO_IDENTITY="1"), capture_output=True, text=True)
    assert result.returncode == 1 and "找不到唯一有效签名身份" in result.stderr
    assert not (root / "lampyris-signing").exists()
    pem = "-----BEGIN PRIVATE KEY-----\nfixture\n-----END PRIVATE KEY-----"
    result = subprocess.run(["bash", str(SCRIPT)],
        env=dict(env, ASC_API_KEY_P8=pem), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert not (root / "lampyris-signing").exists()
    subprocess.run(["bash", str(SCRIPT), "--cleanup"], env=env, check=True)
print("签名脚本模拟验证通过：缺失配置、成功、失败及清理；未访问真实凭据或Apple")
