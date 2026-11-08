# keymap — 编码方案键位字根图（可复用）

给练习/学习界面用：把"哪个键挂哪些字根"画成 QWERTY 键位图，并支持敲键点亮、答案键位描边。

```
keymap/
├── Sources/KeyRootLayout.swift    # 数据模型 + TSV 解析 + bundle 加载（仅 Foundation）
├── Sources/KeyboardMapView.swift  # AppKit 视图（键名字根 + 其它字根 + 分区着色 + 高亮）
├── data/key-roots-wubi86.tsv      # 生成物：五笔 86 的键位字根分布
├── tools/build_key_roots.py       # 从 B0 运行时资源派生
├── spec/keymap-schema.md          # TSV schema 与加方案步骤
└── tests/test-key-roots.py        # 契约测试（schema/覆盖/幂等/体积）
```

- 数据与视图分离：换方案只换一份 TSV + `schemeID`，视图代码不动（ADR-315）。
- 零网络、零遥测；资源是 bundle 内只读文件。
- 生成：`python3 modules/keymap/tools/build_key_roots.py`

宿主导入：`platforms/macos/build.sh` 编译 `modules/keymap/Sources/*.swift` 并把
`data/key-roots-wubi86.tsv` 拷进 `Contents/Resources`。
