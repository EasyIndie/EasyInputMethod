# 164 关于页显示构建号

## 变更

关于页副标题：`0.1.5 · 构建 13 · 开源中文输入法`（`CFBundleShortVersionString` + `CFBundleVersion`）。
构建号缺失时只显示版本号；诊断复制文本格式不变。

## 验证

- 构建 + 快照测试（about-light/about-dark）；
- `make verify`；
- 发布后实机打开「关于」确认。

## 版本

0.1.5 / build13。
