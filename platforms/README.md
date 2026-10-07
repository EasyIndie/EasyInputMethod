# platforms/

各平台宿主。**引擎 100% 复用 `crates/`**，这里只放平台接入薄壳。

| 目录 | 宿主 | 技术 | 阶段 |
|---|---|---|---|
| `macos/` | InputMethodKit | Swift + Rust `staticlib` | P1 |
| `windows/` | TSF (COM) | Rust + `windows` crate（失败则 C++ 薄壳） | P3 |
| `linux/` | Fcitx5 addon | C++ 薄壳 + Rust C ABI | P4 |
| `android/` | `InputMethodService` | Kotlin + JNI | P5 |
| `ios/` | 键盘扩展 | Swift + `staticlib` | P5 |

约定：

- 宿主只做三件事：**捕获按键 → 调用 C ABI → 渲染候选窗**；
- **没有任何业务逻辑**在宿主里；
- 不直接读写配置文件（走 `ime-config` 的 C ABI）；
- 具体见 `docs/技术方案.md` §10。
