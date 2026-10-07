# packaging/

安装包与分发脚本。

| 平台 | 形式 | 阶段 | 签名 |
|---|---|---|---|
| macOS | `.pkg` 或安装脚本 | P1 | **P1 不签名**，手动安装 + Gatekeeper 放行说明 |
| Windows | 安装器 / 便携版 | P3 | 正式阶段 Authenticode |
| Linux | deb / rpm / AUR / Flatpak | P4 | 包签名 |
| Android / iOS | apk / ipa | P5 | 正式阶段 |

规则：

- 安装包**不得**包含任何网络组件或附加推广内容；
- 每个 release 附 **SBOM** 与可复现构建说明（见 `docs/隐私与安全.md` §4）；
- 安装/卸载必须干净：不遗留后台进程、不写系统级配置（除输入法注册外）。
