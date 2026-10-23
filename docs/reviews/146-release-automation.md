# 146 发版自动化：签名 appcast 与 Release 工作流（ADR-265）

## 交付

- `packaging/macos/release-appcast.py`：离线生成 Sparkle 兼容 `appcast.xml`：
  计算 ZIP 长度/SHA-256，用 OpenSSL Ed25519（`pkeyutl -sign -rawin`）签名，**自检验签**后再写 XML；
  拒绝非 https/带凭据/带 fragment 的下载地址、空 ZIP、非数字 build、缺失私钥；只输出摘要（含签名），绝不打印私钥。
- `packaging/macos/tests/test-release-appcast.py`（5 项）：生成的 appcast 能被 `feed.py` 解析并选中、签名可被 OpenSSL 独立验证、
  非 https 拒绝、空/缺失 ZIP 拒绝、非法 build/缺失私钥拒绝；OpenSSL 不支持 Ed25519 时自动跳过。
- `.github/workflows/release.yml`：tag `v*` 触发 →
  `make verify` → `make macos-offline-tests` → 通用构建 → Developer ID 签名/公证（复用 `ci-sign.sh` 与既有 secrets）→
  以 `LAMPYRIS_UPDATE_PUBLIC_KEY` 构建更新程序 → 用 `LAMPYRIS_UPDATE_PRIVATE_KEY` 生成 appcast 并用更新程序自检 →
  `gh release create <tag> <zip> appcast.xml` → `always()` 清理签名材料。
  另外校验 tag 与 Cargo 版本一致，失败即停。
- `docs/更新发布流程.md` 增补实际脚本/工作流与本地演练命令。

## 现在就能做的本地演练（不需要 GitHub）

```sh
openssl genpkey -algorithm ED25519 -out /tmp/test-key.pem
ditto -c -k --keepParent platforms/macos/build/Lampyris.app /tmp/Lampyris-test.zip
python3 packaging/macos/release-appcast.py --zip /tmp/Lampyris-test.zip --build 99 \
  --short-version 0.1.0 --url https://example.com/Lampyris-test.zip \
  --private-key /tmp/test-key.pem --out /tmp/appcast.xml
python3 - <<'PY'
import sys; sys.path.insert(0,'packaging/macos')
import feed, pathlib
print(feed.newest_release(feed.parse_appcast(pathlib.Path('/tmp/appcast.xml').read_bytes()), '6'))
PY
```

## 边界与未完成

- 工作流未在真实 tag 上跑过（没有真实私钥/公钥变量与发版授权）；首次发版需要人工核对版本、构建号与资产。
- 私有仓库/企业代理、镜像回退、下载确认 UI、灰度仍未实现。
- 私钥进 secret 意味着 CI 可签出被客户端信任的包：建议同时离线保存、限制 workflow 触发权限，按文档执行轮换。
- 未改动已装 build6、生产数据与输入源；无 tag / Release。
