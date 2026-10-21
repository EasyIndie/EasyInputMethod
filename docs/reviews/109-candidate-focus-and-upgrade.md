# 109 — 候选双高亮与升级路径复核

2026-10-21，B arm64/macOS27。用户在统一开发包594c8c6（执行5b5ad43c…990568b）手工确认：wq候选框可见、方向键可浏览、输入模式可切换；同时报告两候选高亮。该手工结果解决108中导航/切模式的物理键对照缺口，保留自动化未通过过程；尚无逐项提交/新增领域词物理键通过结论。自有文稿`platforms/macos/build/manual-108-pbtr6n6i/萤火虫手工验收-108.txt`/窗口1902为用户保留，勿自动关闭或重写其内容。

## 最小复现与修复

CandidateLabel原先为hover绘制0.30填充、keyboard focus绘制0.18填充，两项同时满足各自状态时会出现双填充。真实AppKit回归在旧版明确失败`hover must not duplicate filled keyboard focus`（16.721s，日志/private/tmp/lampyris-109-before.log）。ADR-238先记录规则后修改：只有键盘焦点填充，非焦点hover用secondaryLabelColor描边；点击/空格语义不变。覆盖亮暗、焦点移入悬停项、失焦和复用清理。离屏回归不替代本修复的原生安装验收。

## 升级能力源码复核

- 正式包`platforms/macos/install.sh`拒绝覆盖不同版本，相同内容无操作；`uninstall.sh`默认备份应用并保留config.toml/user-dictionary.tsv，只有显式--purge-data才移走数据。
- 因此已有离线手动升级路径：切ABC、移除输入源、注销登录确认宿主退出、默认卸载保留数据、安装签名新版、重新添加。新版会加载原配置/个人词及自己的系统表；不能用全新安装/清数据来代替保留升级验收。
- 固定开发身份`macos-imk-dev.py`已在108从旧包替换到594c8c6，备份previous.app并保留私有数据；不等同于正式安装器A/B升级通过。
- 没有自动联网查新/自动下载更新。当前任务只澄清已有能力，不引入联网更新器或新增配置。
- 正式RC的A/B升级保留、异常恢复及回退仍未验证；数据格式未来变化必须另写ADR及迁移/备份策略。

## 本批验证

`test-candidate-presentation.py`修复后通过（9.299s，/private/tmp/lampyris-109-after.log），严格宿主构建零诊断通过（/private/tmp/lampyris-109-build.log）。两种外观实际layer状态覆盖，与用户物理屏幕复验分别记录。
