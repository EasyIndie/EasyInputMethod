# 104 — B 机新候选隔离验收（进行中）

2026-10-20，B（MacBook-Air / arm64 / macOS 27.0.1）。本报告不继承报告 103 的 PASS；候选身份见同名 schema 2 JSON；仅凭真实证据逐项改判。

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

## 隔离包已安装，等待用户添加源

- 候选锁定：`8eb872ff9b585d8b769f6fb3784285dcc3d81606`；正式 universal 构建 run `39396417287` 已成功。
- 隔离 arm64 公证 run `39396425237` success；zip SHA `e719875d5349256f541bb2496e80afaa4005d91207286a71e071c8453a9b71a1`，执行 SHA `8e8df20b901615d9d0e1c61bdcf32a04b81bd50931de190594a1e4e551dd362a`。
- SOURCE-COMMIT、TARGET-ROOT、requested/built arm64 与实际 lipo 一致；codesign strict、公证 Developer ID、stapler 全过。
- 两份实体包已安装并精确注册，源名称「萤火虫隔离验收 3b030dda」；尚未发键、选择或启用。注册后 TIS 尚无 owned 源，等待用户系统设置添加；不可见/-50 时按 ADR-130/131 重新登录。
- 用户当前源已从初始搜狗拼音切为 ABC；不覆盖此选择。新增源/重新登录后，必须读取实际当前源再创建 selection journal。
- 安装后真实执行文件/config/词库 SHA 与基线逐项一致。
- ADR-220 的性能发键守卫补齐，相关回归（自有资源 9、矩阵 8、基线 5、TextEdit 9、功能 8、HUD 7、owned-probe 4）及 make verify 通过；本地测试工具改动不改变候选产品源码。

原始证据已归档至 `104-evidence/`：基线、前后输入源、隔离身份、下载/信任核验/注册日志。`arm64-macos27` 当前仍 BLOCKED，等待用户添加输入源及实机矩阵，不创建虚假的 PASS。

## 正式候选身份与当前门禁

- 正式 universal zip SHA：`d5e8f30a4eb8bd6f43b496dee65998c3776fe5634813bf5c47da2fb6b625eccb`。
- 正式执行 SHA：`4e9986578fc30828daf5810335a22800e357dab407a304064af1c8b853c12781`。
- 源码包 SHA：`81c5eaa0d5858ed92216dd161ca447a0c6dc7e70f812f593b87b1c4fee0ec0a9`；SOURCE-COMMIT 与两种 CI head 均为 `8eb872ff9b585d8b769f6fb3784285dcc3d81606`。
- 架构、摘要 sidecar、codesign strict、Notarized Developer ID、stapler 均通过。CI 已完成完整离线回归与离线重建；本机只验证归档，未安装正式包。
- 当前机器报告：**pass 1 / fail 0 / skip 0 / blocked 22**，仅 package-validation PASS，check 预期返回 3。B 平台项仍未改判，任务未完成。
