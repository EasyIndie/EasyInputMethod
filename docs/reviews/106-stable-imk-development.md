# 106：固定身份 IMK 开发迭代

日期：2026-10-21。关联 IT-01、ADR-230；产品RC仍为3728dfc，本报告不是新RC验收。

## 当前状态（签名包安装后，以本节为准）

- PR [#56](https://github.com/EasyIndie/EasyInputMethod/pull/56)最新59ee533四门禁全通过（CI39526751254），合入main **b652cd6**。固定开发公证任务 [39527358251](https://github.com/EasyIndie/EasyInputMethod/actions/runs/39527358251)成功；[机器证据](106-stable-imk-evidence.json)绑定源码、zip/执行SHA、设备与未验项。
- B已安装 `~/Library/Input Methods/LampyrisIMKTest-d4fcecfb-af99-4b9a-a590-55fa99e16f05.app`，系统目录枚举的实际名称为 **萤火虫开发 d4fcecfb**。严格签名、项目Developer ID、Gatekeeper、公证票据、源码绑定和四份词表逐字节核验通过；签名包直接normal探针exit0。
- 使用同一签名载荷实际完成安装→替换→previous.app回退，三次实际源集合均与开始相同，数据保留。这只证明未启用时的包级交易，不证明不同版本热更新或客户端输入。证据 `platforms/macos/build/stable-imk-dev/signed-install.log`、`signed-replace.log`、`signed-rollback.log`、`signed-native.json`。
- 当前ABC，实际启用集合无固定开发源，未主动注册/启用/切源或向客户端发键。全注册目录里的default.enabled=true仍不是实际启用证明；实际列表用dev-state.swift的includeAllInstalled=false。
- 私有测试词已经FFI删除，私有mode恢复mixed；生产执行/config/词库三SHA仍与105一致，生产宿主未运行。未改旧105候选。
- **下一步**：用户在系统设置添加“萤火虫开发 d4fcecfb”（若“＋”找不到，保存工作后手动注销再找）。确认实际启用后先做自有窗口输入，再构建同根、不同执行SHA包验证免移除/添加/注销更新及真实输入；A机另初始化其独有长期根。调试附加与正式RC门禁仍待。

## 官方依据与边界

[Apple DTS于2026年6月的回复](https://developer.apple.com/forums/thread/775526)确认系统设置发现新输入源暂无已知免注销方法，反馈FB23026482。不能由此推断每次同身份二进制更新都必须注销，也不能保证同身份更新一定免注销。

[Xcode官方支持附加运行进程](https://developer.apple.com/documentation/xcode/diagnosing-and-resolving-bugs-in-your-running-app)，但调试签名权限与正式Developer ID包不同；本次不为公证包开启get-task-allow。性能采样应单独记录有无调试器，不把断点下的耗时计入16ms门槛。

## 使用流程

日常引擎、候选UI和菜单先用 `make macos-dev`，无需登记输入源。只有IMK调度/预编辑/跨应用验证才进入长期开发源。

```sh
# 每台设备一次；再次调用返回原UUID，不创建新身份。
make macos-imk-dev ACTION=init
# 复制此命令输出的绝对根，提交给main上的公证工作流：
python3 scripts/macos-imk-dev.py root

gh workflow run isolated-imk-notary.yml --ref main \
  -f development=true -f arch=arm64 \
  -f target_root="$(python3 scripts/macos-imk-dev.py root)"
# A机将arch改为x86_64；下载解压工作流产物，不修改签名资源。

make macos-imk-dev ACTION=install APP="/绝对路径/Lampyris.app" ARGS=--stop-host
```

开发根固定为 `~/Library/Application Support/LampyrisIMKDev/lampyris-imk-<UUID>`。其owner是所有权声明，不是第二配置；config.toml仍经ime-config，个人词库仍用既有API。根/owner为0700/0600，生产Lampyris根不动。

首次安装后，用户手动添加“萤火虫开发 <UUID前8位>”；若系统未发现，保存工作后手动注销一次。每次换包前结束组合并切到ABC，工具不自动切源、增删源、改系统缓存或注销。`--stop-host`只停止精确开发包可执行路径对应的进程；有其他持有者或启动竞态则拒绝换包。签名、项目Team、Gatekeeper、公证票据、完整输入源声明和数据根均校验。

旧包保留在开发根的 `replacement-*/previous.app`，换包失败自动回放；成功后保留供回退。主动回退可把该previous.app作为同一install命令的APP，仍须通过全部校验。备份不放在Input Methods中，避免额外登记副本。每次记录installation.json中的执行SHA、源码提交、换包前后当前源及实际启用集合；数据不清空。此工具不把包级成功标为真实输入成功。

## 必须补的原生实验

1. 首次启用后记录实际源集合、当前源、宿主PID/执行SHA，使用已有自有窗口/逐批焦点协议验证wq→你、nihao→你好及Esc。
2. 切ABC，构建同一根的新包并换包；不移除/添加、不注销，确认新PID/新执行SHA，重复输入。比较启用集合及真实生产数据摘要。
3. 以previous.app回退并验证，再做失败/中断恢复。A/B独立记录，不能跨机继承。
4. 若旧菜单或旧宿主仍缓存，不杀系统服务、不清系统偏好，记录失败并使用既有移除/添加或注销路径。

长期开发源可变，不能代替不可变RC、正式安装升级、首次登记、独立重建及五日试用。现有UUID临时候选不迁移、不移除，105等待用户添加的候选仍保留。

## 工程验证历史（签名包安装前）

- 本地arm64/macOS27.0.1：固定开发根原生normal/failure/INT/TERM退出0/7/-2/-15；错误owner及过宽权限均拒绝exit3。证据 `platforms/macos/build/stable-imk-dev/native-final.json`。这是自建ad-hoc隔离宿主直接进程验证，不是系统IMK客户端输入。
- 新9项开发工具回归覆盖固定身份、真实数据目录不创建、符号链接/宽权限/多根拒绝、开发源正在使用时零换包/零停止、路径不符零信号、保留数据/旧包、登记声明变化拒绝、并发换包零修改、最终校验失败回滚。现有隔离6项、CI根/架构4项通过。
- 完整离线41文件187项：38文件首次通过，3项系统服务沙箱失败后正常权限重跑通过；原始失败保留于 `/private/tmp/lampyris-dev-offline.log`，不删去失败历史。actionlint与make verify零诊断通过（`/private/tmp/lampyris-dev-final-verify.log`）。
- 本机固定根 `LampyrisIMKDev/lampyris-imk-d4fcecfb-af99-4b9a-a590-55fa99e16f05` 已初始化，重复调用不换UUID；测试词已通过FFI移除，私有mode恢复mixed。未安装/登记/启用开发源，无真实客户端发键。
- 生产执行535d546f…、config3bc1117c…、词库74f76e92…与105一致；实际当前ABC，启用集合未变。
- 未决：main公证开发包、首次发现/添加、同身份不同执行SHA的免注销换包、旧包回退、A/B真实客户端及调试器附加。仅前置通过，不把脚本/mock/直接进程测试计为以上原生通过。

补充原生证据：精确路径自建宿主停止通过；ad-hoc包被Developer ID门禁拒绝、未安装。换包持有owner文件的排他锁，并发调用在修改前拒绝；失败不会移动不是本次安装产生的目标包。
