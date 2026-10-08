//! 拼音后端 trait 与候选模型。

/// 拼音候选（后端内部表示）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PinyinCandidate {
    /// 候选文本（单字或词）。
    pub text: String,
    /// 归一化拼音码：无调、空格分隔（简拼候选为小写首字母串）。
    pub pinyin: String,
    /// 权重（真实词频，ADR-013）。
    pub weight: i32,
    /// 是否为简拼（首字母）命中。
    pub is_initial: bool,
}

impl PinyinCandidate {
    pub fn new(
        text: impl Into<String>,
        pinyin: impl Into<String>,
        weight: i32,
        is_initial: bool,
    ) -> Self {
        Self {
            text: text.into(),
            pinyin: pinyin.into(),
            weight,
            is_initial,
        }
    }
}

/// 拼音后端查询接口（对应 ADR-008 §8.1，按本卡裁剪）。
///
/// 签名设计理由：
/// - `Send + Sync`：`Session` 要求 `Send`，后端未来可能以 `Arc` 共享给多线程宿主，
///   故在 `Send` 之上放宽到 `Sync`；
/// - `segment` 单独暴露：音节切分是拼音的独立子能力，便于单测与整句引擎复用；
/// - `convert` 返回 [`PinyinCandidate`] 而非 `ime_core::Candidate`：后端只表达拼音域的
///   候选（含 `is_initial` 标记），由 [`crate::PinyinEngine`] 适配为核心候选模型，
///   保证后端可插拔、可替换（ADR-008）；
/// - `reverse_lookup`：字/词 → 拼音（反查，ADR-008 §8.1）。
pub trait PinyinBackend: Send + Sync {
    /// 后端名称（诊断/日志用）。
    fn name(&self) -> &'static str;

    /// 把连续 ASCII 拼音切成合法音节序列；无法完全切分返回空 `Vec`。
    fn segment(&self, input: &str) -> Vec<String>;

    /// 查询候选（全拼 + 简拼），按权重降序，最多 `max` 条。
    fn convert(&self, input: &str, max: usize) -> Vec<PinyinCandidate>;

    /// 反查：单字或词 → 无调拼音（空格分隔）；未知返回 `None`。
    fn reverse_lookup(&self, text: &str) -> Option<String>;
}
