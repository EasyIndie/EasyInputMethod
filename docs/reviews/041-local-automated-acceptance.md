# 041：本地逐场景自动验收记录

日期：2026-10-16。对应ADR-192、T-LOCAL-ACCEPTANCE与IT-03。

用户要求先本地自动化，历史手工覆盖没有确定步骤与结果。本轮补可重复的记录入口，暂停合入、公证与安装；不补造历史逐项PASS。产品代码维持a5689def36e34265e2d9ea6d9e9a3f34898148e5，主目录既有代码未覆盖，B仍1621a6d。

## 实际结果

macOS 27.0.1 / arm64；执行时间UTC 13:22:34—13:23:19（北京时间21:22）。六组全部退出0，60场景PASS，62张原生离屏截图，96份哈希清单产物。运行前后产品/测试身份一致；测试变更当时未提交，15份测试源码快照随证据保存，不能把当时HEAD说成已包含测试变更。

| 组 | 场景数 | 覆盖 |
|---|---:|---|
| 菜单视图 | 4 | 状态无对号、三宽度右对齐、复制状态、亮暗/模拟高亮/禁用绘制 |
| 菜单与会话 | 12 | 模式循环/显式选择、状态切换、设置同步、热键、写入失败恢复、入口与词库 |
| 设置 | 10 | 分组/数量、快捷键与重绑定、四项说明基线24pt、主题、保存失败、词库会话、重开 |
| 候选 | 9 | 内容、直接AX选择动作、翻页及对齐、警告、长词、缺字显示/原文上屏、旧视图 |
| 关于/反馈与词条表单 | 12 | 亮暗表单及按钮、关于文案/圆角控件、模拟外链成功/失败、隐藏父窗、私有粘贴板 |
| 学习区 | 13 | 现有事实、默认值、开关/快捷键/冲突、宽度、旧视图、亮暗对比、滚动/视口 |

完整逐项预期、实测值和时间见运行目录report.html/report.md/report.json；不是仅依据截图或属性存在就判通过。每个checkpoint在既有业务断言通过后记录，进程失败或缺失场景不能汇总PASS。

- 产品文件集合SHA-256：`9f10e4b69e0c77e828efb7e6fc6fd8754efac490cf23716550bf01607ef74a03`。
- Cargo.lock SHA-256：`e6bd07a36b099b099ea739bafd6f6f45218dceb42dbf0e4bbead9161ddcd42d5`。
- 每组另存实际探针可执行文件SHA、依赖锁SHA、原始观测与日志；探针临时二进制不保留，可用源码快照重建。
- 完整离线矩阵：27文件95项通过；其中新增记录校验器10项为合成fixture拒绝路径测试，不计作60个产品组件场景。
- `make verify`：通过，零诊断，隐私检查117产物；`git diff --check`通过。
- 首轮记录代码的Swift类型转换导致编译失败，原失败报告保留于recorded-20261016-first；修正后另建新目录运行，未覆盖失败历史，未把它归因于产品缺陷。

## 本地证据及复现

主目录持久证据：`platforms/macos/build/local-acceptance/recorded-20261016-verified/`，含HTML/Markdown/JSON、源码快照、原始值、截图、清单。旁目录`verification-20261016/`保存verify和27/95离线矩阵日志。构建证据被git忽略，不冒充已提交仓库附件。

在独立工作树执行（主目录Makefile保持原样）：

```sh
make -C /Users/joker/.codex/worktrees/menu-state-shortcuts/EasyInputMethod macos-local-acceptance
python3 /Users/joker/.codex/worktrees/menu-state-shortcuts/EasyInputMethod/platforms/macos/tests/run-local-acceptance.py --check /Users/joker/Documents/EasyInputMethod/platforms/macos/build/local-acceptance/recorded-20261016-verified
```

每轮新目录，失败也保留。离线证据复核已对主目录复制品通过；检查完整ID、源码/测试快照稳定、原始观测与汇总一致、进程退出、必需图/日志/探针身份、文件哈希。清单用于一致性复核，不是第三方签名或防恶意改写承诺。

## 正式验收仍缺什么

本轮scope为native-offscreen-components。未打开系统菜单、未发送桌面按键、未启用VoiceOver，外链为模拟，使用私有配置/词库与命名粘贴板。亮暗为组件指定外观，并非系统辅助显示/真实桌面验收；学习事实测试也不证明拆字全量覆盖。

正式schema 2未放宽，本地报告中23项正式门禁全部明确BLOCKED：实际IMK传递和菜单跟踪、物理键盘及VoiceOver、安全客户端/字段与布局、真实IMK性能、系统外观/多屏、设备A兼容、独立复现及五工作日等须同候选另取证。既有口头确认保留为用户反馈，未还原不存在的步骤。自建结构库仍按ADR-190放在MVP后。

本轮只本地提交测试与文档，不推送、不合入、不安装；后续先依据明确缺口选择下一项测试。
