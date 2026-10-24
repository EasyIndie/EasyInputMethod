# 179 ADR-285 合并后的签名宿主静态复验（未安装）

## 身份与来源

- 主线：PR #143 在 head `01410750fb51a23474478d527932e813ce31eee0` 的 check/dco/fuzz/macos 四 CI 通过后，以 merge commit **`612020ddcfd7e7c66e599502346336894ea67bda`** 合入；固定 dev 已快进同步。
- 自动验收：`macOS Acceptance Package` run **`40096030727`**（success）；`make verify`、离线回归、严格 universal 构建、Developer ID 签名/公证、源码重建及附件上传步骤全部成功。
- 下载至忽略目录 `platforms/macos/build/acceptance-179-review/`，**未安装、未切源、未发键、未写真实配置/词库**。不是 Release 或带独立更新程序的 DMG。

| 对象 | SHA-256 / 结果 |
|---|---|
| `Lampyris-0.1.12-universal.zip` | `2a2e24973658cb95330797f422e929d74055b35347f42f472a79f390dbbd8a42`（随附 `.sha256` PASS） |
| `Lampyris-0.1.12-source.tar.gz` | `ea98f367efce750cf76fbc332d72fa337b0bd848819245855ae9d5f7f197bb5e`（随附 `.sha256` PASS） |
| ZIP 内 `Contents/MacOS/Lampyris` | `ea8b3a39f460cfa02253471f479e5f895ad117f1f1608281c5a1b4612b690a8e` |
| SOURCE-COMMIT | bundle 和源码 tarball 均为 `612020ddcfd7e7c66e599502346336894ea67bda` |
| 身份 | `cn.jokerhub.inputmethod.Lampyris`，`0.1.12/build20`；宿主及 TIS helper 均为 `x86_64 arm64` |
| Apple 静态核验 | Developer ID / Team `2N62934Y28`；`codesign --verify --strict --deep`、`xcrun stapler validate`、`spctl --assess --type execute` 均 PASS |

## 网络导入与局限

- 对**本签名候选**分别执行 `nm -u -arch arm64` 和 `nm -u -arch x86_64`，检查 ADR-285 同一组 `socket` / `connect` / DNS / send / recv 等已知导入，均未命中；两架构均有 `_OBJC_CLASS_$_LampyrisInputController`。旧候选 main `56c2457` 在相同检查下有六个导入，见报告178。这是**新产物的静态门禁 PASS**，不是运行时零外联证明。
- 该包仍为 **build20**（与已发布生产 v0.1.12/build20 相同，但执行 SHA 不同），只能作代码与签名对应性、静态符号研究；不可当作已发布新版本/用户升级包或覆盖正式身份。ZIP 不含新签名 `LampyrisUpdateCheck.app`，不能检验本轮独立更新程序取消/失败/成功路径。
- 本轮没有运行新宿主；`-dead_strip` 对真实 IMK 按名称加载、候选窗、焦点等行为尚须隔离原生验收。同一新候选仍需持续动态外联检查、A/B 客户端及最终 RC 门禁。旧宿主的单次 `lsof` 空值不继承为本候选结果。

## 下一步

1. 为独立更新程序确定**不触碰生产身份、不发正式版**的签名测试载荷来源；若变更签名/CI 协议先写 ADR，不能用本附件冒充更新程序。
2. 从 main 新构建号的同一候选取得双 SHA，确认用户是否授权在隔离身份安装/切源后再做原生行为与动态外联；当前未获明确替换生产包授权，禁止覆盖 v0.1.12/build20。
