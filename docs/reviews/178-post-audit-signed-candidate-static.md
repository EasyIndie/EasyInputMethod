# 178 审计修复后的签名候选静态核验（未安装）

## 边界

- 仅从已合并的 `main` `56c2457170071030b41d6a00825fa36cfbfdbaf3` 取得自动工作流 `macOS Acceptance Package` run `40092840370`（success）；不是从 dev 文档归档提交构建。
- 本轮只下载到忽略目录 `platforms/macos/build/acceptance-178-review/` 并离线解包核验；**未安装、未切输入源、未发键、未修改真实配置或词库**。已装 v0.1.12/build20 执行 SHA 仍为 `c09c2d11749dea9a4347930972817e5262e682c971653f0618c420e7ad9e77a3`。
- 本工作流产物是**输入法宿主**与对应源码，不含独立 `LampyrisUpdateCheck.app`；不能作为 ADR-271 Swift 更新 UI 成功/失败/取消的原生测试载荷，也没有新更新程序的签名身份/执行 SHA。

## 静态证据

| 项目 | 结果 |
|---|---|
| workflow | `40092840370`，head `56c2457`，success；附件 `Lampyris-macos-acceptance-56c2457…` |
| ZIP | `Lampyris-0.1.12-universal.zip` SHA-256 `c5db6eb37d1444671c20b19721f10fd01f5c5ef2366a5098e2f807dd24ebff52`；附件 `.sha256` PASS |
| 对应源码 | `Lampyris-0.1.12-source.tar.gz` SHA-256 `1544701617a09754d06b16074ce7dc030b6c40c562950c8ee2554d0af5917700`；附件 `.sha256` PASS；源码与 bundle 内 `SOURCE-COMMIT` 均为 `56c2457170071030b41d6a00825fa36cfbfdbaf3` |
| bundle | `cn.jokerhub.inputmethod.Lampyris`，`0.1.12/build20`，宿主和 TIS helper 均为 `x86_64 arm64` |
| 候选执行 SHA | `6f650629e85ecfaf716b6cd72d4ace9b37708b18cb53fe9645bfc61ae37b2118`（与已装 `c09c2d…` 不同；没有替换） |
| Apple 核验 | `codesign --verify --strict --deep`、`xcrun stapler validate`、`spctl --assess --type execute` 全 PASS；Team `2N62934Y28`，Developer ID、hardened runtime |

**版本约束**：候选代码不同而 `CFBundleVersion` 仍为 20。此包仅可用作签名/代码对应性及隔离研究证据，**不可**冒称下一正式发布版本、同 RC 性能/输入验收结果，不能用来覆盖当前生产包。正式升级必须先明确新版本/构建号及分发载荷身份。

## 隐私核验边界与新发现

- 对精确已装 PID 78677（路径属于旧已装 `Lampyris.app`）执行一次 `lsof -nP -a -p 78677 -i`，输出为空：只是一时点旧进程快照，**不是新候选动态零外联**，也不能代替长时抓包。
- 在候选宿主可执行文件的 arm64 和 x86_64 两片上用 `nm -u` 均发现 `_connect`、`_getaddrinfo`、`_recvfrom`、`_sendto`、`_socket`、`_socketpair` 导入；旧已装包 arm64 也有同一组。宿主源码搜索未发现直接调用网络 API，但存在符号不能当作“产物无网络符号”PASS，也不表示实际建立了连接。静态归因（例如链接的 Rust 标准库或系统组件）、最终包动态检查仍待；不擅自为去除符号更改架构/链接协议。
- `make verify-no-network` 只扫描本地 `target/` 中被枚举的产物及已知依赖名，没有扫描这个签名 `.app`，因此其 PASS 不覆盖上述候选符号。本报告核验的旧签名产物因此不能被追认零网络导入；后续门禁与处理方案见 ADR-285，不能靠白名单忽略或直接宣称零网络能力。

## 后续隔离归因与工程修复（ADR-285，未包含在本报告所核验的旧签名候选内）

- 将同一 Swift+Rust staticlib 链接分为三组：纯 Swift 无上述导入，加入 `ime_config_schema()` FFI 调用后出现六个导入，给同一链接加 `-dead_strip` 后消失（实验文件仅在忽略目录 `platforms/macos/build/acceptance-178-review/link-probe/`）。这定位为静态链接携带未引用代码的工程问题，不证明过去产物实际联过网，也不证明系统框架将来不使用网络。
- ADR-285 先记录决策，再让 `build.sh --strict --universal` 用 `-dead_strip`，逐架构检查最终宿主导入；本机 arm64/x86_64 均无上述网络导入，`LampyrisInputController` ObjC 类符号仍保留，ad-hoc 严格签名及全部离线回归通过。此构建只在本地**未安装**，不是新的公证候选；真实 IMK 装载与同包动态零外联仍待验证。

## 下一步 / 判定

1. 更新程序的受影响路径：在**非生产身份、私有根**取得绑定合并 main 的新独立更新程序签名载荷，确认其 ZIP/执行 SHA 后才安排取消/失败/成功与备份/回滚/临时文件原生复验；现有 `macOS Acceptance Package` 不提供该载荷。不可为省步骤擅自打 tag/Release 或覆盖旧已装包。
2. 签名宿主与更新程序正式下一版本应先递增构建号；同一候选再完成所需客户端、性能、动态零外联与第三方验收。此报告只关闭**静态身份核验**，不关闭原生更新、隐私或最终 RC 门禁。
