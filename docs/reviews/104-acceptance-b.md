# 104 — B 机新候选隔离验收（进行中）

2026-10-20，B（MacBook-Air / arm64 / macOS 27.0.1）。本报告不继承报告 103 的 PASS；源码锁定、公证包身份与原始证据齐备后再建立 schema 2 JSON。

## 设备基线

- 初始源码：`6ed5da1a4d7128378fcab174a180983944cab7bd`，main，与 origin/main 同步。
- 旧生产执行 SHA：`535d546f9de10541498e123dbb99fde078d37ebe1f2291dc52da8b008a7b1420`；Developer ID Application: Zhizhou Wang (2N62934Y28)，spctl accepted；宿主 PID 17339。
- 真实 config：SHA `3bc1117cc3379a4c6a100bc6d2cf3ddd3bfa37a25739437a32087a87935c7550`，1942 字节，8 个显式快捷键项；不清除、不修改。
- 真实词库：SHA `74f76e92a6cab0eb312d73a4eec575e8d17a9d919a47630bbde0a2f827da7137`，492 字节，29 行。
- 原输入源：`com.sogou.inputmethod.sogou.pinyin`；`source-state state` 已只读复核完整启用集合。
- 私有根：`/private/var/folders/z0/1h35x82j7d767_fm_x3tvdsh0000gn/T/lampyris-imk-3b030dda-b3f5-4424-a45c-90c5cfabfbf7`；0700，owner 0600，内容等于目录名。

## 构建前置与进度

- 初次隔离 CI：[39395207876](https://github.com/EasyIndie/EasyInputMethod/actions/runs/39395207876)，arch=arm64，绑定上述私有根；构建已 success；尚未安装或发键。
- 正式包 CI [39384028937](https://github.com/EasyIndie/EasyInputMethod/actions/runs/39384028937) 在 TextEdit 离线回归失败，未进入签名。根因与最小修复见 ADR-219；修复后重新锁定提交，正式 universal 与隔离 arm64 包必须来自相同提交。
- 初始 `make verify` 因沙箱无法写 cargo advisory lock 中止；沙箱外重跑全绿，隐私检查 182 个产物通过。非产品失败。
- TextEdit 场景生成与 mock 修复后 9 项相关回归通过；沙箱外完整离线回归 40 文件 / 174 例仅性能矩阵旧文案断言失败，修复后该文件 7 项回归通过。tools private copy 在沙箱外通过。最终 make verify 全绿；远端完整门禁待重跑。
- 性能脚本静态检查发现直接 osascript 发键绕过自有窗口守卫（trace 的设置/关于、矩阵的 ensure_host/commit_latency/variant）；按边界在守卫修复前不运行这些路径，性能采集暂记工具阻断。

## 判定与边界

所有 B 机实机项目当前均为待验，不声明 `arm64-macos27` PASS。其他结构性阻断不在本轮解决，最终允许检查器以 BLOCKED（3）退出，但不允许格式/证据错误、FAIL 或 SKIP。A 机报告 103 仅供历史比较，新候选 Intel 项待复验。

平台差异：交接脚本附带的旧 selsrc 无参数查询返回空；重新编译的 source-state 在图形会话可读精确源。沙箱内 codesign 查询曾报内部错误，沙箱外验证 accepted；菜单索引、设置默认分区、TCC 提示仍待实测。

证据工作目录：`platforms/macos/build/acceptance-b-104/`（不入库）；已记录 `baseline.json`，后续逐项归档可审核原始证据。
