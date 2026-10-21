# 118 — 用户词库同步失败后可重试

## 问题与修复

审阅IT-12学习持久化链路时发现：Store::flush在打开文件之前就把dirty清零。文件不可用导致第一次flush失败后，第二次直接成功，Drop也不再尝试同步。这是源码与临时词库回归确认的问题，不是报告115长尾的已确认根因。

先追加ADR-243，再补临时词库回归；旧代码真实失败于第二次flush错误返回Ok。最小修复只把dirty清零移到文件sync_all成功之后；文件打开或同步失败保留重试义务，不改原子写、学习时机、TSV格式、数据或配置。

## 验证

临时路径：学习写入→移走文件→连续两次flush均报NotFound→恢复文件→flush成功且文件字节与重载词条保持→成功后再移走文件，无新修改的flush仍为no-op。无真实词库参与。

[旧版失败日志](118-evidence/before.txt)、[修复后完整ime-dict测试](118-evidence/after.txt)。cargo test -p ime-dict（13项）与make verify零诊断通过，200产物隐私断言通过。未新增网络/遥测/依赖/unsafe或配置；核心forbid(unsafe_code)保持。

## 边界

不模拟断电、硬件缓存或父目录同步错误；父目录原有best-effort语义保持，Drop仍不能向用户返回错误。未改当前已装a3853aa签名包，尚无本修复实机/安装验收。测试计时117仍等待用户切源手工确认，属于独立分支docs/native-stage-validation；不将此修复计作性能改善或最终MVP通过。
