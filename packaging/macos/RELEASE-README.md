# 萤火虫 macOS 0.1.0

默认离线的五笔/拼音混合输入法，GPL-3.0-or-later。请查看 BUILD-INFO.txt 的架构、构建版本和 signed_release；false 表示仅供审核的本地候选，不能用于分发安装。

## 安装

签名公证的最终包才可安装。用 Finder 解压发行 ZIP，或运行 `ditto -x -k Yinghuo-0.1.0-universal.zip ./unpacked`，进入解压目录。请使用保留 Unix 执行权限的解压工具；安装器会拒绝缺少执行权限的程序。终端运行：

```sh
./scripts/install.sh --app ./Yinghuo.app --dry-run
./scripts/install.sh --app ./Yinghuo.app
```

注销/重新登录，在系统设置 → 键盘 → 文字输入添加萤火虫。当前用户目录是默认位置；系统域可由管理员执行 `sudo ./scripts/install.sh --app ./Yinghuo.app --system`。同版本重复执行无操作，不同版本先卸载。不要关闭 Gatekeeper；验证失败请停止安装。

## 卸载

先切换 ABC，在系统设置移除萤火虫，注销/重新登录确保宿主退出，再运行：

```sh
./scripts/uninstall.sh --dry-run
./scripts/uninstall.sh --input-source-removed
```

系统域需加 `--system` 并由管理员执行。应用移动至安装域的 Application Support/yinghuo/uninstalled 备份；用户 config.toml 与 user-dictionary.tsv 保留。设置路径为 `~/Library/Application Support/萤火虫/`。

## 核验与复现

SHA256SUMS 覆盖签名应用、源码与附件；包旁另附 ZIP 校验和。SBOM.cdx.json 是 ime-ffi 闭包的 CycloneDX 1.5 依赖清单，原始依赖许可在 DEPENDENCY-LICENSES。数据的独立许可与来源见 DATA-SOURCES.md、data-sources.toml、DATA-LICENSES；派生核心词表按 CC-BY-SA-4.0 提供，保留出处和修改说明。

SOURCE 包含本次 git 提交的全部源码、Cargo.lock、工具链声明及锁定依赖 vendor。安装对应 Rust、Python 3 与 Command Line Tools 后，进入 SOURCE 运行 `cargo build --locked --offline --release -p ime-ffi`，然后 `./platforms/macos/build.sh --strict`；这些构建不需要下载词表，已登记默认数据随源码提供。原始词表再生成步骤见 SOURCE/platforms/macos/README.md。

比较未签名可执行文件和默认数据 SHA-256；Swift/SDK/架构应与 BUILD-INFO.txt 相同。Apple 签名、公证及 ZIP 元数据不保证逐字节一致。支持目标 macOS 13+；只有已记录的实机环境经过验证，其他版本/架构不能据此推断已验收。

隐私验证：源码运行 `make verify-no-network`；在系统装载后用 `lsof -nP -a -p <宿主PID> -i` 核查无网络连接。候选包的最终多应用/常驻内存验收仍以发布验收记录为准。
