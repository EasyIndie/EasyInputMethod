# 萤火虫 macOS @VERSION@

默认离线的五笔/拼音混合输入法，GPL-3.0-or-later。首版拼音用于常用字词输入，支持全拼、显式音节分隔（如 xi'an）及全首字母简拼；不提供分段选词或整句语言模型。混输把同一编码分别按五笔和拼音查询合并，不支持在同一组合中任意交替两种编码。请查看 BUILD-INFO.txt 的架构、构建版本和 signed_release；false 表示仅供审核的本地候选，不能用于分发安装。

## 安装

签名公证的最终包才可安装。用 Finder 解压发行 ZIP，或运行 `ditto -x -k Lampyris-@VERSION@-universal.zip ./unpacked`，进入解压目录。请使用保留 Unix 执行权限的解压工具；安装器会拒绝缺少执行权限的程序。终端运行：

```sh
./scripts/install.sh --app ./Lampyris.app --dry-run
./scripts/install.sh --app ./Lampyris.app
```

安装器会调用包内 helper 自动注册并启用输入源；用 ⌃Space 或输入法菜单选中萤火虫即可（若未出现，重启登录一次）。当前用户目录是默认位置；系统域可由管理员执行 `sudo ./scripts/install.sh --app ./Lampyris.app --system`。同版本重复执行无操作，不同版本先卸载。不要关闭 Gatekeeper；验证失败请停止安装。

## 从旧版升级（保留配置和个人词库）

目前使用离线手动升级，没有自动检查或下载新版。请取得并核验签名公证的新版包；安装器会拒绝直接覆盖不同版本。

1. 结束当前组合；卸载脚本会自动切回 ABC 并禁用输入源（宿主仍在运行时先注销一次）。
2. 从旧版包执行默认卸载：`./scripts/uninstall.sh`（helper 可用时无需 `--input-source-removed`）。不要加`--purge-data`；默认会备份旧应用并保留配置和个人词库。
3. 从新版包执行`./scripts/install.sh --app ./Lampyris.app --dry-run`，检查通过后去掉`--dry-run`安装。系统域安装/卸载两步都需对应的`--system`及管理员权限。
4. 按安装步骤重新登录、添加并选中萤火虫，核对原配置、个人词、三模式输入和版本信息。新版内置系统词表随应用更新。

保留的用户数据位于`~/Library/Application Support/Lampyris/`。升级前可自行复制此目录备份；异常时保留备份和旧包，按相同移除/退出/安装流程恢复旧应用。涉及未来数据格式迁移的版本须遵循对应发布说明，不能假定任意版本均可直接降级。当前正式RC仍需在目标A/B设备完成保留升级和恢复验收；开发身份的换包成功不等同正式升级验收完成。

## 卸载

直接运行（脚本会切回 ABC 并禁用输入源）：

```sh
./scripts/uninstall.sh --dry-run
./scripts/uninstall.sh --input-source-removed
```

系统域需加 `--system` 并由管理员执行。应用移动至安装域的 Application Support/Lampyris/uninstalled 备份；用户 config.toml 与 user-dictionary.tsv 保留。设置路径为 `~/Library/Application Support/Lampyris/`。

## 核验与复现

SHA256SUMS 覆盖签名应用与附件；包旁另附 ZIP 校验和。SBOM.cdx.json 是 ime-ffi 闭包的 CycloneDX 1.5 依赖清单，原始依赖许可在 DEPENDENCY-LICENSES。数据的独立许可与来源见 DATA-SOURCES.md、data-sources.toml、DATA-LICENSES；派生核心词表按 CC-BY-SA-4.0 提供，保留出处和修改说明。

本包按 GPL-3.0-or-later **不含源码**（第 6(d) 条，见 `SOURCE.txt`）：对应源码为**与本包同处发布**的 `Lampyris-@VERSION@-source.tar.gz`（含本次提交全部源码、Cargo.lock、工具链声明及锁定依赖 vendor）。安装对应 Rust、Python 3 与 Command Line Tools 后，解压源码包并在其根目录运行 `cargo build --locked --offline --release -p ime-ffi`，然后 `./platforms/macos/build.sh --strict`；构建不需下载词表，已登记默认数据随源码提供。原始词表再生成步骤见源码包内 platforms/macos/README.md。

比较未签名可执行文件和默认数据 SHA-256；Swift/SDK/架构应与 BUILD-INFO.txt 相同。Apple 签名、公证及 ZIP 元数据不保证逐字节一致。支持目标 macOS 13+；只有已记录的实机环境经过验证，其他版本/架构不能据此推断已验收。

隐私验证：源码运行 `make verify-no-network`；在系统装载后用 `lsof -nP -a -p <宿主PID> -i` 核查无网络连接。候选包的最终多应用/常驻内存验收仍以发布验收记录为准。
