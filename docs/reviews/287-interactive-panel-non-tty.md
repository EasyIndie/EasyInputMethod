# 287 — 交互式面板验收在非 TTY 下崩溃修复

> 2026-11-15。用户直接执行 `make macos-dev` 时脚本在 `selectors.register(sys.stdin)` 崩溃（EINVAL），窗口来不及使用。

## 1. 现象

```
File "run-panel-interactive.py", line 45, in <module>
    reader.register(sys.stdin, selectors.EVENT_READ)
OSError: [Errno 22] Invalid argument
```

Claude Code 的 `!` / `Bash` 环境里 stdin 不是可 `select()` 的终端（管道/`/dev/null`），
而脚本假定了一个可轮询的 `sys.stdin`。崩溃发生在 `try` 内，`finally` 已终止隔离进程并把
临时目录标为 `RETAINED`，但窗口已经关闭，无法验收。

## 2. 修复

- 用 `sys.stdin.isatty()` 区分：TTY 走原来的「输入 `close` 结束」；非 TTY 不注册 stdin，
  只轮询子进程，**关闭窗口即结束**，并打印对应提示。
- 交互会话中若真实 `config.toml` / `user-dictionary.tsv` 有变化，改为 **WARN** 而不是
  「protected files changed」异常：预览进程只写私有根（`ime_config_init(work/config.toml)`），
  人工会话期间已装输入法可能在其它窗口正常学习（写真实词库），不能据此判定预览越界。
  自动化模式的严格隔离断言仍由 `run-panel-isolation.py` 负责。

## 3. 验证

- 非 TTY 启动 → 关闭窗口 → `PASS interactive cleanup: owned process exited; real files unchanged`，
  退出码 0，临时目录已删除；
- `run-panel-acceptance.sh --isolation-probe` 4 项仍 PASS。

## 4. 关于真实数据

手工验收期间，真实 `user-dictionary.tsv` 从 2,046 行变为 2,060 行（新增 14 条五笔词条），
`config.toml` 的 `candidate.show_wubi_learning` 变为 `true`（02:20）。自动化隔离探针（同样会
`ime_config_init(私有根)` 并 `setString("mode", …)`）仍 PASS：真实文件在预览进程外未被写入。
因此这些变化与已装输入法在其它窗口的正常学习/⌥L 切换一致，**未回滚**（属于用户真实数据）。

## 5. 关联

`platforms/macos/tests/run-panel-interactive.py`、报告 286。
