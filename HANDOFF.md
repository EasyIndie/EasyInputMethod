# HANDOFF — 当前状态

## 0. 元信息

- 更新：2026-10-19 22:55 / pi（deepseek-flash）· **IT-14 前置：CI 已出「隔离身份 + Developer ID」x86_64 包并在 A 装好；
  卡在「新装第三方输入法需一次重新登录才被发现」（TIS 选择 `-50`），探针未跑**
- 分支：`main` @ `c60bd88`（已推送；工作树 clean；仅 main）
- 阶段：A 生产包装 `07bbb2f`（执行 `681fb1c8…`）；报告 097/098/099/100/101；
  **报告 102 进行中（出包/安装完成，系统发现 BLOCKED 待重新登录）**
- 最近验证：`make verify` 全绿（c60bd88）；隔离公证 run `39269308347` success

## 1. 安装与数据

| 设备 | 系统 | 已装包 | 状态 |
|---|---|---|---|
| A（`bot`，Intel / macOS 13.7.8） | x86_64 | 生产 `07bbb2f`（执行 `681fb1c8…`，Notarized Developer ID） | 宿主 **91040 仍在运行**；真实 `config.toml` 22:28 实测 `809e2cae…`、词库 `b5c18a7e…`（用户在用，跑完以回读为准）；输入源**当前由用户切换**（勿擅自切走） |
| A（同上） | x86_64 | **隔离测试包** `cn.jokerhub.inputmethod.LampyrisIMKTest.fd15c596-…`（CI run `39269308347`，commit `c60bd88`，zip `d14a395b…`） | 已装 `~/Library/Input Methods/LampyrisIMKTest-fd15c596-….app`；私有根 `/private/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-fd15c596-…`（0700 + `owner` + `selection-state.json` + `source-state`）；TIS 已枚举 2 个自有身份但**系统设置/菜单都看不到**，`TISSelectInputSource` = `-50` |
| B（`joker`，arm64 / macOS 27） | arm64 | `17053e1`（`535d546f…`） | 报告 093；未参与本轮 |

- 本轮**未**设置 `LAMPYRIS_SUPPORT_DIR`（隔离包把 config/词库写在私有根内）；`launchctl getenv` 为空。
- 隔离包核对：`codesign --verify --strict` ✓、`stapler validate` ✓、`spctl` = accepted / Notarized Developer ID（Team `2N62934Y28`）、
  `x86_64`、`IMKTestRoot` 已绑定到上面的私有根。
- 取包：`gh run download 39269308347` → `packaging/out/a-102/`。公证 workflow 输入：`target_root=<私有根>`、`arch=x86_64`。

## 2. 本轮完成（2026-10-19）

| 提交 | 内容 | 报告 |
|---|---|---|
| `c60bd88` | 隔离公证 CI 支持 `arch=arm64/x86_64/universal` 与任意系统临时目录目标根（ADR-216） | 102 |

- 工作流/工厂/测试：交叉构建（Rust `--target` + Swift `-target <arch>-apple-macosx13.0` + `lipo`）、
  签名前复核架构与绑定、目标根白名单化；`test-isolated-ci.py` 3 项 + `test-isolated-imk.py` 6 项 + `make verify` 全绿。
- 历史（报告 094–101）：HUD + ADR-215 数据根 + 真实 IMK 隔离验收 + 独有身份注册 + 机器可校验报告
  （`check`：pass 9 / blocked 14）。

## 3. 当前未决

- **IT-14 前置（阻塞点）**：新装隔离输入法在 macOS 13 上**需一次重新登录**才会被系统发现
  （与 ADR-130/131 在设备 B 的现象一致）：系统设置「＋」和菜单栏输入法菜单都看不到，
  `source-state select-owned` → `TISSelectInputSource` 返回 `-50`、父源 `enabled` 仍 0。
  证据：`docs/reviews/102-evidence/`（`102-select-blocked.txt`、`02/04/05-state-*.json`）。
- 重新登录后：系统设置添加「萤火虫隔离验收 fd15c596」→ 跑 `run-installed-{textedit,safari,terminal}-probe.py`
  四路径（normal/failure/INT/TERM）→ 收尾 → 把报告 101 对应 BLOCKED 改判。
- 若登录后 `$TMPDIR` 路径变化：绑定失效，必须用新根重跑 CI（约 4 分钟，`arch=x86_64`）。
- **IT-01 剩余**：微信聊天隔离草稿（BLOCKED）、完整剪贴板多类型恢复（仅命名剪贴板 + mock 证据）。
- **IT-12/IT-15/IT-23**、**IT-03 剩余 14 项 BLOCKED**：未开始。
- **A 工具链差异**：`make macos-offline-tests` 在 A 必红（Swift 5.8.1 + 高负载 `swiftc` 超时）；Swift 侧门禁以 CI 为准。
  注意 A 机上**单文件 `swiftc` 也要 3 分钟左右**（`source-state` 实测），命令超时别给 300s。

## 4. 下一步

### 4.1 重新登录后（同一会话可直接执行）

```sh
R=/private/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-fd15c596-2402-4fcb-94e4-5bfe5e47f8dc
ls -ld "$R" "$R/owner"                      # 0700 / 0600，owner 内容 = 目录名
# 若根被清掉：仅按 ADR-131 重建空根，不恢复测试配置内容
python3 - <<'PY'
from pathlib import Path
root = Path("/private/var/folders/x7/hhbm75rn6vz_37yjj5rsq9yc0000gn/T/lampyris-imk-fd15c596-2402-4fcb-94e4-5bfe5e47f8dc")
root.mkdir(mode=0o700, parents=True, exist_ok=True)
(root/"owner").write_text(root.name); (root/"owner").chmod(0o600)
PY
# 重新编译 helper（约 3 分钟；先 mkdir module-cache）
swiftc -O -warnings-as-errors -module-cache-path "$R/module-cache" \
  platforms/macos/tests/isolated-imk/source-state.swift -o "$R/source-state"
# 复核已装包 + 当前 TIS 状态
codesign --verify --strict "$HOME/Library/Input Methods/LampyrisIMKTest-fd15c596-2402-4fcb-94e4-5bfe5e47f8dc.app"
"$R/source-state" state "$R"
```

1. 用户在系统设置添加「萤火虫隔离验收 fd15c596」（或确认 2 个自有身份已 enabled）。
2. 用**当时实际原源**刷新 `$R/selection-state.json`（`state` 输出 + `identity`，0600）。
3. 依次跑三组探针（每组 4 场景；发键前 `tools/macos-probe/guard-focus.sh`，中途失焦立即 BLOCKED）：
   `python3 platforms/macos/tests/run-installed-textedit-probe.py "$R" "$R/source-state" --scenario normal|failure|INT|TERM`，
   Safari / Terminal 同理。TCC 若弹「自动化」授权，交给用户点允许，不绕过。
4. 收尾：`"$R/source-state" restore-original` → `disable-owned` → 用户移除输入源 → `lsregister -u` 后删实体包 → 删私有根；
   回读生产执行 SHA / 宿主 PID / 真实 config+词库 SHA；写报告 102 结果并把 101 对应项改判。
5. `make verify` → 提交 `docs: report 102 …` → 推送。

### 4.2 备选（不依赖重新登录）

- 补测 101 里 `focus`/`multi-display`（不需要签名），把 BLOCKED 再减 2 项；
- 采 IT-12 引擎/渲染基线（`run-perf.sh`、`render_perf.swift`）。

## 5. 授权与边界

- 不自动注销/重启/解锁——**重新登录由用户执行**，本会话已按此停在登录前。
- 不热替换生产包；隔离包是独立身份，未停宿主 91040、未动真实 config/词库。
- 配置只经 `ime-config`；不写 `UserDefaults`/`com.apple.HIToolbox`；数据隔离用 `LAMPYRIS_SUPPORT_DIR`（本轮未用）。
- 失败即停、保留证据；不伪造 PASS；截图/口头确认不记为正式 PASS。
- 一轮只测一个包；探针遵守 `tools/macos-probe/README.md`；每批发键前跑 `guard-focus.sh`。

## 9. 会话日志

- 2026-10-19 / pi：**IT-14 前置出包并安装，停在重新登录前**。`c60bd88` 让隔离公证 CI 支持 x86_64/universal 与任意系统临时根（ADR-216）；run `39269308347` 出 x86_64 Notarized Developer ID 包（zip `d14a395b…`），已装 A 并核对签名/绑定/架构；TIS 枚举 2 个自有身份但系统设置与菜单均不可见、选择 `-50`（与 ADR-130/131 一致）→ 需用户重新登录后继续（报告 102 进行中）。
- 2026-10-19 / pi：发布门禁中段：A 装 `07bbb2f`；097 所有权 / 098 数据根 / 099 真实 IMK / 100 独有身份注册 / 101 机器报告（pass=9 blocked=14）。
- 2026-10-19 / pi：HUD 收口（095/096）；ADR-214 修复（firstRect 优先 + attributes 兜底）。
- 2026-10-19 / pi：A 全新安装 `17053e1`（094），HUD D7/D8 记录后由 ADR-214 定夺。
- 2026-10-18 / pi：B 新 UI 验收通过（093），翻页光学对齐（091）、头部字号/留白（092）。
