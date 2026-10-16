# 萤火虫输入法 — 规范命令
# 用法: make help
SHELL := /bin/bash
CARGO ?= cargo
CLEAN ?= ./scripts/check-clean.sh   # 零诊断门禁：见 docs/开发工作流.md §4
FUZZ_SECONDS ?= 30

.PHONY: help verify fast fmt fmt-check lint test deny verify-no-network fuzz clean check-workspace usage-report macos-preview macos-dev macos-offline-tests macos-local-acceptance hooks

macos-offline-tests: ## 执行 macOS/分发全部离线 Python 回归（不操作桌面）
	PYTHONDONTWRITEBYTECODE=1 python3 platforms/macos/tests/run-offline-tests.py

macos-local-acceptance: ## 本地逐场景自动验收及持久证据（离屏，不操作桌面）
	PYTHONDONTWRITEBYTECODE=1 python3 platforms/macos/tests/run-local-acceptance.py

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

verify-no-network: ## 断言核心产物与依赖不含网络能力
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
