# 176 竞品 macOS 输入法的 App Store 渠道调研

> 调研日期：2026-10-24。目的：为“仅保留网站/DMG 渠道”（ADR-284）提供外部参照。
> 方法：iTunes Search/Lookup API（`entity=macSoftware`，中国区/美国区）+ 各产品官网下载页。
> 结论是**渠道事实**，不评价产品质量；App Store 搜索结果会随地区/时间变化。

## 结论摘要

- 主流第三方 macOS 中文输入法（搜狗、百度、微信、鼠须管、清歌、落格、万能五笔）均以**官网 DMG/安装包或 GitHub Releases** 分发；
  **没有发现它们的 macOS 输入法本体在 Mac App Store 上架**。
- App Store 中能搜到的“搜狗输入法”“百度输入法”条目是 **iOS/iPadOS 键盘应用**，
  不是 macOS InputMethodKit 输入法；部分条目可通过 “MacDesktop” 在 Apple Silicon 上运行 iOS app，但不等于系统输入法。
- App Store 里有不少**输入法切换/管理工具**（如搜狗输入法切换助手、AutoSwitchInput），它们是辅助工具，不是输入法引擎。
- 清歌、落格的 **iOS 版**在 App Store；它们的 **macOS 版**仍是官网直接下载/购买。

## 逐项核对

| 产品 | macOS 分发方式 | App Store（macOS 输入法） | 证据 |
|---|---|---|---|
| 搜狗输入法 Mac | 官网 DMG/安装包 | 未发现；App Store 的“搜狗输入法”为 iOS 键盘 | <https://pinyin.sogou.com/mac/>；`com.sogou.SogouInput`（iOS，最低 iOS 14） |
| 百度输入法 Mac | 官网 DMG/安装包 | 未发现；App Store 条目为 iOS 键盘 | <https://shurufa.baidu.com/mac>；`com.baidu.inputmethod`（iOS，最低 iOS 13） |
| 微信输入法 Mac | 官网下载 | 未发现 macOS 输入法条目 | <https://z.weixin.qq.com/> |
| RIME / 鼠须管 Squirrel | 官网 DMG + Homebrew + GitHub | 未发现 | <https://rime.im/download/> |
| 清歌输入法 | Mac 版官网直接下载 | 未发现 macOS 版；iOS 版在 App Store | <https://qingg.im/> |
| 落格输入法 macOS 3 | 官网购买/下载 | 未发现 macOS 版；iOS 版在 App Store | <https://im.logcg.com/loginputmac3> |
| 万能五笔 | 官网下载 | 未发现 | <https://www.wnwb.com/> |

## 对萤火虫的含义

1. **DMG 是中文 macOS 输入法的常规渠道**，不是“落后方案”；用户对 DMG + 安装器的接受度高。
2. Mac App Store 的输入法本体案例很少，说明沙盒、输入源注册、首次启用体验确实存在门槛；
   这与 ADR-257/260 的“未验证前不宣称可行”一致。
3. 双渠道如果使用同一 bundle/input source 身份，会出现输入源与数据目录冲突；
   竞品普遍没有同时维护两套同身份输入法，侧面说明单渠道更可控。
4. 因此正式发布维持**网站 + DMG**；App Store 沙盒原型仅保留为研究资产，不进入发布流程。

## 局限

- “未发现”不等于绝对不存在；App Store 搜索受地区、关键词、下架状态影响。
- 本调研没有分析各竞品的公证、更新器、许可证或审核历史，只回答“是否有 macOS App Store 版本”。
- 若未来重启 MAS 评估，应重新做一次检索并核对 Apple 最新审核规则。
