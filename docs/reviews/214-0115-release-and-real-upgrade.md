# 214 0.1.15 发布与 0.1.14 → 0.1.15 真实升级（含一处窗口文案缺陷）

> 承接报告 [213](213-updater-ships-with-package.md) 的第 4 项（当时 BLOCKED：无发布、无私钥、无 publish 作业）与 §5-P5（执行 SHA 突变）。
> 本篇只记新增结论与证据，通用内容不重复。

## 1. 结论摘要

| 项 | 结果 |
|---|---|
| 0.1.15 / build 24 发布 | **完成**：tag `v0.1.15` = 候选提交 `c7dd401`，Release run `40499343349` success |
| Release ZIP 与验收候选一致 | **PASS**：两者同为 `00b7b20d…`（tag 打在候选提交上，回避了「同号不同 SHA」） |
| DMG / 更新程序 / 源码资产 | 全部生成并签名公证；appcast `sparkle:version=24` |
| 站点 | Pages run `40499933508`，`input.jokerhub.cn` 回读 `v0.1.15 · 构建 24` |
| **真实跨版本升级**（0.1.14 → 0.1.15，经更新程序联网） | **PASS**（报告 213 第 4 项的一半，见 §3） |
| 更新器自更新（升级时替换 `~/Applications` 本体） | **仍未验**：0.1.14 的更新程序只替换宿主；需 0.1.15 更新程序 + 0.1.16 才能演示 |
| 新发现缺陷 | 更新窗口标题读的是**更新程序自己**的版本 → 装完仍显示旧版本，用户会判定「没更新」（§4，已修） |
| 报告 213 §5-P5（执行 SHA 突变） | **结案**：不是产品缺陷，是会话期间用户把 0.1.14 装回去了（§5） |

## 2. 发布身份

| 项 | 值 |
|---|---|
| 版本 / 构建 | 0.1.15 / 24 |
| 源码提交 | `c7dd401bab823c0771316cfec715fcb92950e4ec` |
| ZIP | `00b7b20d317801017307374532c88daae6689ef69e99f6a8fadf04ff9edf9195`（7,021,364 B） |
| DMG | `40ab9fc8738aba72a6768114d95596b70712d93a9a4eb39fc5ae17e596fa48d8`（`codesign --strict` / `stapler validate` / `spctl` = Notarized Developer ID 全 PASS） |
| 更新程序 ZIP | `6a4c707db3da95342d12dbee4bef7c7f8effd2058fc24ff1a3f24e156e211ca1` |
| 源码包 | `646767b649b75ad5b03933ce9d2f71c18841eeb1ebe9923add482ac7ce2e0ef8` |
| appcast | `sparkle:version="24"`，Ed25519 签名与 receipt 中的签名一致 |

**流程教训**：`macos-acceptance` 按 ADR-293 只对产品字节变化构建，纯文档合并不产候选；而 Release 工作流要求「tag 提交存在成功验收产物」。
所以第一版 tag（打在发布材料提交上）直接失败，改tag 到候选提交 `c7dd401` 才通过——这也让发布 ZIP 与已核验候选**逐字节相同**。

## 3. 真实跨版本升级（PASS）

前置：air 上装着 0.1.14/build 23（用户在用），把 0.1.14 的官方更新程序从 Release 资产装进 `~/Applications`。

| 步骤 | 结果 |
|---|---|
| 菜单「检查更新…」 | 第一次点开的是**浏览器**——0.1.14 的 `UpdateEntry.updaterURL()` 只认旧名 `~/Applications/Lampyris Update.app`（按 bundle id 查找是 ADR-294 之后才有）。把更新程序改成旧名后，菜单正常拉起窗口 |
| 检查 → 下载 → 验签 → 安装 | 完成；窗口显示「已安装构建 24」 |
| 落地核对 | 宿主 `…/Input Methods/Lampyris.app` = **0.1.15 / build 24**，执行 `4ec77887…`（= 候选执行 SHA）；宿主 PID 18019 已自动重启；输入源仍是 `Lampyris.default`，无需重新添加 |
| receipt（0600） | `payloadSHA256=00b7b20d…`（= Release ZIP）、`signature=2+xa8Yzn…`（= appcast `edSignature`）、`installedExecutableSHA256=4ec77887…`，`previous` 指向 `updates/upgrade-2026-10-27T12-00-46Z-…/backup/Lampyris.app` |
| 旧版本备份 | 备份内为 0.1.14/build 23，可用于回滚 |
| 更新程序 | 仍是 0.1.14/23（老代码不自更新，符合预期；见 §1） |

两次安装（12:00:46、12:13:43）都是同一构建，第二次是幂等重装，receipt 各自一份，未留临时目录。

## 4. 新缺陷：更新窗口标题读错来源（已修）

**现象**：升级成功、状态行写着「已安装构建 24」，标题却仍是「当前版本 0.1.14 · 构建 23」，用户据此判断「还没装 0.1.15」。

**根因**：`UpdateWindowController.versionText` 用 `Bundle.main.infoDictionary`，取的是**更新程序自己**的版本；老更新程序装完新宿主后自己仍是 23，标题永远不动，且安装成功后也不刷新。

**修法**：

- 新增 `InstalledVersion`（`Updater/Sources/WebsiteUpdateCheck/InstalledVersion.swift`）：从**已安装宿主** `location.domain/<target.bundleName>/Contents/Info.plist` 读 `CFBundleShortVersionString` + `CFBundleVersion`，缺失/不全返回「未知」。
- 窗口标题、「没有更高构建」提示都改为读它；**安装成功后重新读一次并刷新标签**，所以从旧更新程序升级也能立刻显示 24。
- 新增 `InstalledVersionTests`（5 例）：读宿主版本、升级后同 location 立即读到新版本、宿主缺失返回未知、Info.plist 缺键返回未知、不取更新程序自身。

## 5. 报告 213 §5-P5 结案

09:27 看到的「执行 SHA 变回旧包 `a165f05c…`」与本次 11:15 观察到的现象同因：**会话期间用户把 0.1.14 装回机器**（`~/Library/Input Methods` 的版本、TIS 条目、正在增长的词库都对得上）。不是产品行为异常；后续验收开始前先做一次「装的是哪个包」的回读即可。

## 6. 仍未关闭

- **更新器自更新**：需 0.1.15 更新程序 + 更高构建号（0.1.16）才能演示；本轮窗口里的「重新打开更新程序」按钮未被触发。
- **`--uninstall`（保留数据）仍留 `uninstalled/`**（报告 213 §5-P3）：语义待 ADR 澄清。
- **air + VoiceOver 装机版掉回 ABC**（报告 210 §3.1）：未定位。
- **0.1.14 用户菜单只能开网页**（无内置更新程序、且只认旧名）：升级到 0.1.15 后消失，发布说明需披露。
- MVP 门禁 IT-14 / IT-15 / IT-22 / IT-23 仍开放。

## 7. 证据路径

`platforms/macos/build/acceptance-air-c7dd401/`（不入库）：`ev-12-old-updater.txt`（装 0.1.14 更新程序）、`ev-13-old-updater-rename.txt`（改回旧名）、`ev-14-after-upgrade.txt`（升级后回读）、`ev-15-upgrade-verdict.txt`（收据/备份/版本来源）、`ev-10-install.txt`（0.1.15 首次安装被安全拒绝）。

## 8. 0.1.16 与「点了没变化」的第二层原因

0.1.16 / build 26 已发布（tag `v0.1.16` = 候选提交 `e54a0c3`，Release run `40505562873`）：
ZIP `4c79be40c501a3e8b13b87f73e6aafb0cebfe9e9094bc8a635cdf32b0733afff`（= 验收候选）、DMG `2e7362c0…`、
更新程序 `09b55c16…`、源码 `09d46020…`、appcast `sparkle:version=26`；站点回读 `v0.1.16 · 构建 26`。

用户第二次反馈「下载并安装后还是没有变化」，取证后是**两层原因叠加**，都不是 0.1.16 的回归：

| 层次 | 事实 | 性质 |
|---|---|---|
| 显示 | 用户看的是 **12:13 那次留下的旧窗口**（标题 `0.1.14 · 构建 23`、备份路径还是 `upgrade-2026-10-27T12-13-43Z`）。它属于 0.1.14 的更新程序进程（PID 17416，**从我在 12:39 删掉的 `Lampyris Update.app` 里启动**），窗口不会自我刷新 | 我的操作制造的环境（删除了正在运行的 bundle） |
| 实际 | 该进程在 12:54:25 确实替换了宿主：`…/Input Methods/Lampyris.app` = **0.1.16 / build 26**，执行 `743fb3c8…`，`codesign --strict` / `spctl` / `stapler` 全 PASS，宿主已重启（PID 23396） | 升级本身成功 |
| 残留 | 同一次安装**没有写 receipt**、`updates/upgrade-2026-10-27T12-54-25Z-…/staging/` 未清理——即「替换成功但收尾失败」。对照 0.1.14 安装器代码，替换后依次是「落地校验 → 计算落地 SHA → 写 receipt → 清理 staging」，能在替换后中断且不触发回滚的只有进程被异常终止这一类 | 环境异常（运行中的 bundle 已被我删除） |

**处置**：结束遗留进程 → 用 0.1.16 Release ZIP 内的更新程序同步 `~/Applications`（现为 0.1.16/26，执行 `f834f198…`）→ 删除那次安装残留的 `staging/`（保留 `backup/` 以便回滚）。
当前状态：宿主 0.1.16/26（PID 23396，输入源 `Lampyris.default` 正常在用）+ 更新程序 0.1.16/26，版本已一致。

**结论与余项**：

- 「真实跨版本升级」（0.1.14 → 0.1.15）已在 §3 证明；0.1.14 → 0.1.16 的宿主同样落地成功。
- **更新器自更新仍未在真机演示**：本轮两次升级分别由 0.1.14、以及被我删除过 bundle 的旧进程执行，都没走到 0.1.15+ 的 `selfUpdate` 分支。下一次发版（0.1.17）时机器上已是 0.1.16 更新程序，点一次即可自然覆盖该分支。
- 落地教训：**升级窗口不要留到下一轮**——旧进程会继续持有旧代码与旧文案；每次换包后先关掉旧窗口再取证。这条写进 `iterate-macos-ime` 的检查项。
