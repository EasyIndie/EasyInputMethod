# T-ITER-13：发布附件与构建元信息

- 状态：进行中（ADR-112附件门禁完成本地回归；构建身份/target预检及日志移除已验证；真实签名候选待验）
- 目标：dry_run和正式发布使用同一核验，包与源码对应。
- 实现：validate-release.py离线读取ZIP/tar，不解压执行。检查二进制/源码各自外部摘要、ZIP全文件摘要、版本/tag/提交、BUILD-INFO已签名声明、实际Mach-O arm64+x86_64及执行权限、默认输入数据、离线源码材料。发布只读取核验输出的四个附件。
- 回归：`PYTHONDONTWRITEBYTECODE=1 python3 packaging/macos/tests/test-validate-release.py`，9项合成测试通过；本机真实universal可执行文件架构检查通过。测试不是Apple签名/公证验证；没有下载最终包、触发Release或提交变更。
- ADR-113：SDK/系统/Xcode从实际构建环境派生，CLT不虚构Xcode；target在编译/暂存清理前预检。4项回归通过，strict universal通过，产物SDK27.0/26A425、Xcode27.0/27A266a、最低13.0与本机实际一致，产品契约核验通过。
- ADR-114：移除生产宿主按键字符NSLog；FFI冒烟/渲染辅助工具补warnings-as-errors。FFI运行时通过，相关宿主编译零诊断。
- 下一步：锁提交后核验真实签名公证附件，执行dry_run；当前工作树含未提交变更，开发包的HEAD字段不能冒称最终源码身份。
- 验收：make verify零诊断、strict universal及隔离预览；最终候选身份与摘要可复核，演练/发布共用门禁，失败不能发布。
- 关联：IT-14/15，ADR-064/065/112；GPL对应源码同页发布。
