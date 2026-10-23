# 148 生产安装升级演练（v0.1.0）

## 结论

生产包已从旧 `17053e1`（执行 `535d546f…`）升级到 **v0.1.0 / build 6**（universal，执行 `5709716c…`），
配置与个人词库**字节未变**；并完成一次「回滚到旧包 → 再次升级」的实机演练，最后新宿主可正常启动。

## 1. 升级（dry-run → apply）

- 来源：仓库默认 GitHub feed `releases/latest/download/appcast.xml`（`sparkle:version=6`），
  用**入库公钥**构建的 `LampyrisUpdateCheck` 验签；ZIP SHA-256 `d225aee7…` 与 Release 附件一致。
- `--apply` 结果：`result=installed`，前后执行 SHA 均记录，旧包备份到
  `~/Library/Application Support/Lampyris/updates/upgrade-20261023T124339-…/backup/Lampyris.app`，
  receipt 写入 `updates/receipts/`（0600）。
- 升级后校验：`lipo -archs` = `x86_64 arm64`、`codesign --verify --deep --strict` 通过、
  `stapler validate` 通过、`spctl` = Notarized Developer ID（Team 2N62934Y28）、build 6。

## 2. 回滚演练

1. 手动把新包移到 `/tmp`，把备份的旧包移回安装路径 → 执行 SHA 回到 `535d546f…`，`codesign` 通过。
2. 再次 `--apply`：第一次因 LaunchServices `lsd` 短暂持有可执行文件被旧逻辑拒绝（**自动回滚，旧包保持完好**）。
3. 按 ADR-269 修复「只终止精确二进制持有者，忽略系统服务持有」后重试：`result=installed`，
   执行 SHA 回到 `5709716c…`，receipt 与备份各新增一份。

## 3. 启动与数据

- 新宿主 `open` 启动成功（PID 85905，无 crash/deny 日志），随后精确停止。
- 生产 `config.toml` SHA `3bc1117c…`、个人词库 `74f76e92…`（29 行）在升级前后完全一致；输入源保持 ABC。
- 备份保留 3 个升级目录（首次升级、失败尝试、回滚后重升），未清理，便于人工恢复。

## 4. 局限

- 未验证「升级时输入源正被使用」的系统行为（演练在 ABC 下进行）；未做 Windows/Linux。
- 未做多镜像/多公钥（ADR-267）、未做下载确认 UI；本次为网站渠道生产包。

## 证据

`docs/reviews/148-install-drill-evidence/`：`00-pre.txt`、`01-apply.log`、`02-post-install.txt`、`03-launch.txt`、
`04-rollback-restored.txt`、`05-reapply.log`、`06-final.txt`。
