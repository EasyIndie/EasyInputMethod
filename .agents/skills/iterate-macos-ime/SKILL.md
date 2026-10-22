---
name: iterate-macos-ime
description: 在已装 macOS 输入法上做「换包 → 验收 → 还原」的快速迭代。当任务涉及安装新签名包、验证已装包行为、写验收报告、或需要反复换包调试时使用。
---

# 已装包快速迭代（macOS）

目标：**一次换包 3 分钟，不重复踩坑**。发布验收仍走用户手动流程（见 §6）。

## 0. 路径选择

| 场景 | 用哪条 | 代价 |
|---|---|---|
| 固定开发身份（ADR-230，真实IMK日常迭代） | `make macos-imk-dev`，见[报告106](../../../docs/reviews/106-stable-imk-development.md) | 首次添加可能注销；后续免注销须A/B实证，不先记PASS |
| 本地迭代（新包调试、复验 UI/行为、只换自己签名的候选包） | **不注销**：`make macos-fast-reinstall` | 几分钟，需要手动加一次输入源 |
| 发布验收（用户正常卸载→安装→添加源） | 注销：`make macos-clean-install` | 一次注销（会终止 agent 会话） |
| 只要看 UI 观感 | `make macos-ui-snapshots` / `make macos-dev` | 秒级，不碰安装目录 |

既有`macos-fast-reinstall`路径的前提只有三条，缺一就停：**输入源已移除**、**宿主已退出**、**包装前校验签名/公证**。

## 1. 不注销换包（推荐）

```sh
# 1) 切回 ABC（可选：tissrc list 看当前源）
tools/macos-probe/bin/tissrc select com.apple.keylayout.ABC

# 2) 用户在「系统设置 → 键盘 → 文字输入」移除「萤火虫」（唯一必须手动的步骤，见 §2）

# 3) 一条命令：校验输入源已移除 → 停空闲孤儿宿主 → 移走旧包/旧数据 → 装新包 → 打印执行 SHA
make macos-fast-reinstall APP=packaging/out/<run>/candidate-XXXX/extracted/Lampyris-0.1.0-universal/Lampyris.app ARGS=--stop-host

# 4) 用户添加「萤火虫」，再选中它
tools/macos-probe/bin/tissrc select cn.jokerhub.inputmethod.Lampyris.default
```

- 脚本对宿主只做 `pkill -x Lampyris`，且必须显式 `--stop-host`；`--keep-data` 保留旧配置/词库。
- 装完 `config.toml` **还没生成**：首次状态写入时才按 Schema 默认值创建（这是「默认行为」验收的干净起点）。
- **不想动用户数据**时加 `--keep-data`（不把真实 config/词库移进 `uninstalled/`）。
- **真实 IMK 验收要隔离学习写入**：`launchctl setenv LAMPYRIS_SUPPORT_DIR /tmp/lampyris-imk-…`（绝对路径）→ 重启宿主 →
  配置/词库全部写到该私有根（ADR-215，报告 098）；验完 `launchctl unsetenv LAMPYRIS_SUPPORT_DIR`。
- 用完还原：输入源 `tissrc select com.apple.keylayout.ABC`，`config` SHA 与宿主/执行 SHA 回读写进报告。

## 2. 输入源自动化：能做到哪一步（实测，报告 095）

| 动作 | 能否自动化 | 说明 |
|---|---|---|
| 查看已启用源 / 当前源 | ✅ | `tools/macos-probe/bin/tissrc list` |
| 选中某个已启用源 | ✅ 且可脚本化 | `tools/macos-probe/bin/selsrc <id>`（打印 `select <id> <rc>` 与切换后 `current`；上一轮已用它自动切回 ABC）。切换后必须回读确认，采样结束切回 ABC；首次添加/移除仍需手工 |
| **首次添加**第三方输入法 | ❌ | `TISEnableInputSource` 返回 0 但源不出现在启用列表、宿主不启动；必须在「系统设置 → 键盘 → 文字输入」里加 |
| 停用/移除 | ❌ | 实测 `TISDisableInputSource` 同样返回 0 但源仍在启用列表、宿主不退出（报告 095c）；只能在系统设置里移除 |

所以快速路径每轮保留**两个**手工步骤：移一次、加一次（各约 10 秒）。**不要**为了省这一步去写 `com.apple.HIToolbox` 的 plist——
那是系统输入源注册表，出问题会污染用户输入法列表。

## 3. 探针（`tools/macos-probe/`）已知坑

| 坑 | 现象 | 正确做法 |
|---|---|---|
| 枚举 TIS 会拉起宿主 | 重启后本来没宿主，跑一次 TIS 查询就冒出 `Lampyris` 进程 | 换包前先 `pgrep -x Lampyris`；脚本会处理孤儿 |
| ⇧ 单按识别不了 | 只发 keyUp 或只发带 Shift 的 keyDown 都不行 | 先发 `keyDown(56, [.maskShift])` 再发 `keyUp(56, [])` |
| ⌥ 组合键不生效 | `⌥F/⌥M` 无反应 | 事件序列要带修饰键自己的 keyDown/keyUp（见探针 `keymod 58 opt` 三连） |
| 菜单索引会变 | 启用源数量不同，产品行索引整体偏移 | 永远**先 `axmenu dump` 再按标题取索引**，别照抄别的机器的序号 |
| `CGWindowList` 的 `on=false` 不可靠 | HUD 明显可见却报 offscreen | 用「截图差分 + OCR」确认可见性，窗口坐标只作参考 |
| HUD 不在 AX 树里（macOS 13） | `AXWindows` 为空，读不到文案 | `CGWindowList` 取 frame + `screencapture -R` + Vision OCR 读文案 |
| 窗口被恢复到屏外 | 显示器布局变化后，窗口 y 为负、坐标离谱 | 先 `AXPosition` 设回屏幕内再测；判读坐标时先 `NSScreen.screens` 看布局 |
| 前台应用会被抢 | `osascript`/`open -a` 之后前台可能不是目标应用；**中途也可能被别的应用抢走**（报告 099：验收中 QQ 抢前台，按键进了用户输入框） | **每一批发键前**都跑 `tools/macos-probe/guard-focus.sh TextEdit`，不通过就停；不在“只检查一次”的假设下连续发键 |
| 合成事件会粘修饰键 | 连续测试后 ⌥/⇧ 状态错乱 | 用 `keyUp` 清一遍修饰键（探针 `clear`） |
| 截图/OCR | 部分机器无录屏权限时截图是旧图 | 两张不同画面比对文件 hash；不行就退回 AX/CG 取证 |
| A 机 Swift 5.8 编不了部分测试 | `make macos-offline-tests` 里 `heterogeneous collection literal` + 高负载 `swiftc` 超时 | Swift 侧以 CI（Swift 6）为门禁；A 只跑 `make verify`、Python 离线回归、原生探针 |
| 关闭文档后窗口对象被销毁（macOS 13） | AppleScript `visible of window id` 报 `-1700` | 先 `exists window id` 再判 `visible`（见报告 097） |

## 4. 验收脚本骨架（照抄改场景）

```sh
E=platforms/macos/build/acceptance-<设备>-<报告号>
mkdir -p "$E"
{ echo "== pre $(date -u +%FT%TZ)"; sysctl -n kern.boottime
  echo "installed=$(shasum -a 256 "$HOME/Library/Input Methods/Lampyris.app/Contents/MacOS/Lampyris" | awk '{print $1}')"
  echo "config=$(shasum -a 256 "$HOME/Library/Application Support/Lampyris/config.toml" | awk '{print $1}')"
  echo "host=$(pgrep -fl Lampyris || echo none)"; } > "$E/00-pre.txt"
# …逐项验证，每项一个证据文件…
swift tools/macos-probe/bin/../tissrc list > "$E/99-restore.txt"   # 还原后回读
```

判定与报告要求见 `docs/reviews/` 里最新一份报告；**失败就写 FAIL/BLOCKED，不伪造 PASS**。

发键铁律：**每次 `typekeys`/`keymod` 之前都先 `guard-focus.sh <目标应用>`**（只检查开头一次不够，见报告 099 的事故）；
中途失焦立即终止、记录 BLOCKED，不要重试、不要“抢回焦点”后继续。

## 5. HUD 专项（踩过最多坑的地方）

- 位置来源：`attributes(forCharacterIndex:)`（AppKit 文本视图，准）→ `firstRect(forCharacterRange:)`（终端）→ 都不行就不显示。
- 客户端必须属于**前台应用**（`bundleIdentifier()` 对比），否则会把提示放到上一个应用的插入点。
- Finder 桌面/图标视图会给出「伪光标」：`length()==0` + Finder 时不显示。
- 矩形必须落在屏内（终端可能返回翻转/像素坐标）。
- 定位偏移可疑时开诊断：`launchctl setenv LAMPYRIS_HUD_DIAG 1` → 重启宿主 → 读 `$TMPDIR/lampyris-hud-diag.log`
  （记录每次 `line<i>` / `first<i>` / `pick`，用完 `launchctl unsetenv LAMPYRIS_HUD_DIAG`）。

## 6. 发布验收（必须注销）

```sh
make macos-clean-install APP=…/Lampyris.app ARGS=--input-source-removed
```
用户手动：切 ABC → 系统设置移除「萤火虫」→ **退出登录**（不是锁定屏幕；脚本只认宿主是否退出）→ 重新登录。

## 7. 收尾清单（每轮都做）

1. 输入源还原 ABC；`config.toml` SHA、宿主 PID、执行 SHA 回读。
2. 自建文档/窗口关闭（不碰用户真实文档）。
3. 证据放 `platforms/macos/build/<acceptance>/`（该目录不入库），报告写证据文件名。
4. `make verify` 全绿 → 固定`dev`提交/推送；同批`dev → main` PR持续跟进至合并或关闭，不按验收轮次另开分支/PR；HANDOFF §1/§3/§4/§9同步（ADR-246/248）。
