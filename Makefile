# 萤火虫输入法 — 规范命令
# 用法: make help
SHELL := /bin/bash
CARGO ?= cargo
CLEAN ?= ./scripts/check-clean.sh   # 零诊断门禁：见 docs/开发工作流.md §4
# 离线回归/本地验收需要 Python ≥3.11（tomllib）；macOS 13 自带的 python3 是 3.9，所以优先挑新版（报告200）。
PYTHON ?= $(shell for p in python3.13 python3.12 python3.11 python3; do command -v $$p >/dev/null 2>&1 && { echo $$p; break; }; done)
FUZZ_SECONDS ?= 30

.PHONY: help verify fast fmt fmt-check lint test deny verify-no-network fuzz clean check-workspace usage-report macos-preview macos-dev macos-imk-dev macos-offline-tests macos-local-acceptance macos-probe-build macos-auto-acceptance macos-soak macos-multi-display macos-ui-contrast macos-ui-snapshots macos-clean-install macos-fast-reinstall macos-installer-build handoff hooks

macos-offline-tests: ## 执行 macOS/分发全部离线 Python 回归（不操作桌面）
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) platforms/macos/tests/run-offline-tests.py

macos-local-acceptance: ## 本地逐场景自动验收及持久证据（离屏，不操作桌面）
	PYTHONDONTWRITEBYTECODE=1 $(PYTHON) platforms/macos/tests/run-local-acceptance.py

macos-probe-build: ## 构建 macOS 实机探针（tools/macos-probe/bin，不安装）
	$(MAKE) -C tools/macos-probe

macos-auto-acceptance: macos-probe-build ## 一键自动验收：热键/上屏 + 五客户端 + 键入延迟/内存/零外联（报告191）
	OUT=$(or $(OUT),/tmp/lampyris-acceptance-$$(date -u +%Y%m%dT%H%M%SZ)) ROUNDS=$(or $(ROUNDS),10) ./tools/macos-probe/acceptance-auto.sh

macos-multi-display: macos-probe-build ## 多屏/缩放/全屏下的候选窗落点（报告202）：逐屏 + 全屏各测一次
	OUT=$(or $(OUT),/tmp/lampyris-multidisplay-$$(date -u +%Y%m%dT%H%M%SZ)) ./tools/macos-probe/multi-display.sh

macos-soak: macos-probe-build ## 久用验收：连续键入 MINUTES 分钟，断言零外联/内存稳态/词库重启不丢（报告192）
	MINUTES=$(or $(MINUTES),5) OUT=$(or $(OUT),/tmp/lampyris-soak-$$(date -u +%Y%m%dT%H%M%SZ)) ./tools/macos-probe/soak-session.sh

macos-ui-snapshots: ## 离屏渲染候选/关于/设置/诊断面板（亮/暗），几秒看 UI 改动，不操作桌面
	./scripts/ui-snapshots.sh

macos-ui-contrast: ## 离屏快照 + 对比度判定（IT-22 机器可判部分，报告197）
	./scripts/ui-snapshots.sh
	python3 tools/macos-probe/contrast-report.py

macos-clean-install: ## 登录后一条命令全新安装（先切 ABC、移除输入源、注销；APP=<bundle 路径>）
	./scripts/clean-install.sh --app "$(APP)" $(ARGS)

macos-fast-reinstall: ## 本地迭代换包（不注销；输入源已移除 + 宿主空闲；APP=<bundle 路径> [ARGS=--stop-host]）
	./scripts/macos-fast-reinstall.sh --app "$(APP)" $(ARGS)

handoff: ## 采集交接状态（只读；SCENARIO=compact|session|agent|device，PROMPT=1 出提示词骨架）
	./scripts/handoff-status.sh $(if $(SCENARIO),--for=$(SCENARIO)) $(if $(PROMPT),--prompt)

macos-imk-dev: ## 固定IMK开发身份：ACTION=init|root|install APP=<签名包> [ARGS=--stop-host]
	python3 scripts/macos-imk-dev.py $(or $(ACTION),root) $(if $(APP),--app "$(APP)") $(ARGS)

macos-dev: ## 重建并启动隔离验收窗口（私有配置/词库与正式菜单组件）
	./platforms/macos/tests/run-panel-acceptance.sh --interactive

macos-preview: ## 历史调试窗口（使用真实配置；日常迭代推荐 macos-dev）
	./platforms/macos/dev-preview.sh

help: ## 列出所有命令
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

check-workspace: ## 内部：确认 workspace 已存在（不存在则报错退出）
	@test -f Cargo.toml || { \
		echo "ℹ️  尚无 Cargo workspace（将在 P1-M0 创建）。当前处于文档阶段。"; \
		exit 1; }

fmt: check-workspace ## 格式化代码
	$(CARGO) fmt --all

fmt-check: check-workspace ## 检查格式（不改动）
	$(CARGO) fmt --all -- --check

lint: check-workspace ## Clippy（warnings 视为错误；零诊断门禁）
	$(CLEAN) $(CARGO) clippy --workspace --all-targets -- -D warnings

test: check-workspace ## 运行全部测试（零诊断门禁）
	$(CLEAN) $(CARGO) test --workspace

fast: check-workspace ## 内环快检（fmt-check + clippy + test；不含依赖/隐私断言）
	$(CARGO) fmt --all -- --check
	$(CLEAN) $(CARGO) clippy --workspace --all-targets -- -D warnings
	$(CLEAN) $(CARGO) test --workspace

hooks: ## 安装本地 git hooks（pre-push 自动跑 make verify）
	./scripts/install-hooks.sh

deny: check-workspace ## 依赖许可 / 漏洞 / 重复依赖检查（零诊断门禁）
	$(CLEAN) $(CARGO) deny check

bootstrap: ## 安装开发依赖（版本固定，见 MVP 审计 SEC-07）
	cargo install cargo-deny --version 0.20.2 --locked
	cargo install cargo-fuzz --version 0.13.2 --locked

verify-no-network: ## 静态扫描已知网络依赖/符号（不代替最终包动态外联核验）
	./scripts/verify-no-network.sh

usage-report: ## 汇总用量/成本（纯本地，不花 token）
	./scripts/usage-report.sh

# verify 是提交前唯一入口：文档阶段只跑隐私断言；编码阶段跑全套。
verify: ## 提交前全量验证（文档阶段只跑隐私断言）
	@if [ -f Cargo.toml ]; then \
		set -e; \
		$(CARGO) fmt --all -- --check; \
		$(CLEAN) $(CARGO) clippy --workspace --all-targets -- -D warnings; \
		$(CLEAN) $(CARGO) test --workspace; \
		if command -v cargo-deny >/dev/null 2>&1; then \
			$(CLEAN) $(CARGO) deny check; \
		elif [ "$${ALLOW_MISSING_DENY:-}" = "1" ]; then \
			echo "⚠️  降级：cargo-deny 未安装，已跳过依赖/许可审计 —— 此结果不可提交（先 make bootstrap）" >&2; \
		else \
			echo "❌ cargo-deny 未安装，无法完成依赖/许可审计。请运行 make bootstrap；如仅作本地探查可 ALLOW_MISSING_DENY=1 make verify" >&2; \
			exit 1; \
		fi; \
		echo "✅ make verify 全部通过（编码阶段）"; \
	else \
		echo "ℹ️  文档阶段：编译类检查跳过，仅运行隐私断言。"; \
	fi
	@$(MAKE) verify-no-network

fuzz: check-workspace ## 解析器 fuzz（需 nightly + cargo-fuzz；FUZZ_SECONDS 可调）
	$(CARGO) +nightly fuzz run dict_parser -- -max_total_time=$(FUZZ_SECONDS)
	$(CARGO) +nightly fuzz run table_parser -- -max_total_time=$(FUZZ_SECONDS)
	$(CARGO) +nightly fuzz run pinyin_parser -- -max_total_time=$(FUZZ_SECONDS)

clean: ## 清理构建产物
	$(CARGO) clean || true

.PHONY: macos-updater-tests macos-updater-build
macos-updater-tests: ## 独立更新检查离线安全/严格并发回归（不请求feed）
	python3 platforms/macos/Updater/verify-vendor.py
	cargo build --locked --release -p ime-ffi
	$(CLEAN) swift test --package-path platforms/macos/Updater --scratch-path platforms/macos/build/updater-tests -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete -Xswiftc -I$(PWD)/crates/ime-ffi/include -Xlinker $(PWD)/target/release/libime_ffi.a

macos-updater-build: ## 构建默认关闭的独立更新检查程序（不安装、不联网）
	cargo build --locked --release -p ime-ffi
	$(CLEAN) python3 platforms/macos/Updater/build.py

macos-installer-build: ## 构建 DMG 图形安装器/卸载器（不安装、不联网）
	$(CLEAN) python3 platforms/macos/Installer/build.py
	$(CLEAN) python3 platforms/macos/Uninstaller/build.py
