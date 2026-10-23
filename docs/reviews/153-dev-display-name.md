# 153 固定开发版名称与图标（ADR-272）

## 变化

| 项 | 旧 | 新 |
|---|---|---|
| 开发版名称（zh） | 萤火虫开发 d4fcecfb（随根 UUID 变化） | **萤火虫 开发版** |
| 开发版名称（en） | 萤火虫开发 d4fcecfb | **Lampyris Dev** |
| 菜单图标 | 与正式版相同的模板图标 | **`LampyrisDevTemplate.png`（右上角点角标）** |
| 正式版 | 萤火虫 / Lampyris (Firefly) | 不变 |

- 新图标由 `platforms/macos/Resources/LampyrisDevTemplate{,@2x}.png` 提供（18/36px，模板渲染）。
- 开发包构建（`platforms/macos/tests/isolated-imk.py`）统一改名并替换图标键；`prepare-isolated-ci.py` 不再拼 UUID 前缀。
- 固定开发包换包允许 **显示名/图标键** 演进（ADR-272），身份、连接名、开发根仍严格一致。

## 验证

| 项 | 结果 |
|---|---|
| 隔离包构建回归 | `test-isolated-imk.py` 6 项通过（断言固定中文名、dev 图标、英文本地化） |
| 开发包安装器回归 | `test-imk-dev.py` 10 项通过（新增：显示名/图标变化允许；服务声明变化仍拒绝） |
| CI 打包脚本 | `test-isolated-ci.py` 4 项通过 |
| 构建元数据 | `packaging/build-number` 未变，仍由 Cargo 版本/构建号派生 |

## 说明

- 名称固定后，输入源菜单里正式版与开发版分别为「萤火虫」「萤火虫 开发版」，图标一个无角标、一个带点。
- 身份未变，因此现有开发源不需要移除/重新添加；显示名在系统菜单下一次刷新即可见（必要时重新登录）。
- 新名称/图标要等下一次开发包（build7）构建安装后才能实机看到；本轮未安装新包、未改动现有开发包。
