//! 萤火虫输入法核心：引擎抽象与会话状态机。
//!
//! 纯逻辑、零 IO、零网络、无平台代码；`#![forbid(unsafe_code)]`。

#![forbid(unsafe_code)]

/// 输入模式。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum InputMode {
    /// 默认：五笔优先 + 拼音兜底。
    #[default]
    Mixed,
    /// 仅五笔。
    WubiOnly,
    /// 仅拼音。
    PinyinOnly,
}

impl InputMode {
    pub const ALL: [InputMode; 3] = [InputMode::Mixed, InputMode::WubiOnly, InputMode::PinyinOnly];

    pub fn as_str(self) -> &'static str {
        match self {
            InputMode::Mixed => "mixed",
            InputMode::WubiOnly => "wubi",
            InputMode::PinyinOnly => "pinyin",
        }
    }

    /// 循环切换：Mixed → WubiOnly → PinyinOnly → Mixed。
    pub fn next(self) -> Self {
        match self {
            InputMode::Mixed => InputMode::WubiOnly,
            InputMode::WubiOnly => InputMode::PinyinOnly,
            InputMode::PinyinOnly => InputMode::Mixed,
        }
    }
}

impl std::str::FromStr for InputMode {
    type Err = ();

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "mixed" => Ok(InputMode::Mixed),
            "wubi" => Ok(InputMode::WubiOnly),
            "pinyin" => Ok(InputMode::PinyinOnly),
            _ => Err(()),
        }
    }
}

impl std::fmt::Display for InputMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// 引擎类型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EngineType {
    CodeTable,
    Pinyin,
}

/// 候选来源。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CandidateSource {
    CodeTable,
    Pinyin,
    Phrase,
}

/// 一个候选。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub text: String,
    pub code: String,
    pub weight: i32,
    pub source: CandidateSource,
    pub comment: Option<String>,
    pub is_prefix: bool,
}

impl Candidate {
    pub fn new(
        text: impl Into<String>,
        code: impl Into<String>,
        weight: i32,
        source: CandidateSource,
    ) -> Self {
        Self {
            text: text.into(),
            code: code.into(),
            weight,
            source,
            comment: None,
            is_prefix: false,
        }
    }
}

/// 一次转换的结果。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ConvertResult {
    pub candidates: Vec<Candidate>,
    /// 自动上屏意向（由协调器复核后放行）。
    pub should_commit: Option<String>,
}

/// 输入引擎抽象。
///
/// 实现必须纯逻辑：不感知平台、UI、网络、文件系统。
pub trait Engine: Send {
    fn convert(&self, input: &str, max: usize) -> ConvertResult;
    fn engine_type(&self) -> EngineType;
    fn max_code_length(&self) -> usize;
    fn reset(&mut self) {}
}

/// 单个按键的处理结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum KeyOutcome {
    /// 键被消费，候选已更新（调用方应刷新候选）。
    Consumed,
    /// 已上屏一段文本。
    Committed(String),
    /// 与本输入法无关，透传给系统。
    PassThrough,
}

/// 会话状态机。
///
/// 持有注册的引擎，按 [`InputMode`] 分派，维护组合缓冲与候选。
#[derive(Default)]
pub struct Session {
    mode: InputMode,
    wubi: Option<Box<dyn Engine>>,
    pinyin: Option<Box<dyn Engine>>,
    composing: bool,
    buffer: String,
    candidates: Vec<Candidate>,
    committed: String,
}

impl Session {
    pub fn new(mode: InputMode) -> Self {
        Self {
            mode,
            ..Self::default()
        }
    }

    pub fn set_wubi_engine(&mut self, engine: Box<dyn Engine>) {
        self.wubi = Some(engine);
    }

    pub fn set_pinyin_engine(&mut self, engine: Box<dyn Engine>) {
        self.pinyin = Some(engine);
    }

    pub fn mode(&self) -> InputMode {
        self.mode
    }

    pub fn set_mode(&mut self, mode: InputMode) {
        self.mode = mode;
        self.cancel();
    }

    pub fn cycle_mode(&mut self) -> InputMode {
        self.set_mode(self.mode.next());
        self.mode
    }

    pub fn composing(&self) -> bool {
        self.composing
    }

    pub fn buffer(&self) -> &str {
        &self.buffer
    }

    pub fn candidates(&self) -> &[Candidate] {
        &self.candidates
    }

    pub fn committed(&self) -> &str {
        &self.committed
    }

    /// 按当前模式返回活跃引擎（M0：Mixed 只走五笔；拼音兜底 M2 接入）。
    fn active_engines(&self) -> Vec<&dyn Engine> {
        let mut engines: Vec<&dyn Engine> = Vec::new();
        match self.mode {
            InputMode::Mixed => {
                if let Some(e) = self.wubi.as_deref() {
                    engines.push(e);
                }
                if let Some(e) = self.pinyin.as_deref() {
                    engines.push(e);
                }
            }
            InputMode::WubiOnly => {
                if let Some(e) = self.wubi.as_deref() {
                    engines.push(e);
                }
            }
            InputMode::PinyinOnly => {
                if let Some(e) = self.pinyin.as_deref() {
                    engines.push(e);
                }
            }
        }
        engines
    }

    /// 处理一个按键。
    pub fn handle_key(&mut self, key: char) -> KeyOutcome {
        if !self.composing {
            if key.is_ascii_lowercase() {
                self.composing = true;
                self.buffer.clear();
                self.buffer.push(key);
                return self.recompute();
            }
            return KeyOutcome::PassThrough;
        }

        match key {
            'a'..='z' => {
                self.buffer.push(key);
                self.recompute()
            }
            ' ' => {
                if let Some(first) = self.candidates.first() {
                    let text = first.text.clone();
                    self.commit(&text);
                    KeyOutcome::Committed(text)
                } else {
                    self.cancel();
                    KeyOutcome::Consumed
                }
            }
            '1'..='9' => {
                let idx = (key as u8 - b'1') as usize;
                if let Some(c) = self.candidates.get(idx) {
                    let text = c.text.clone();
                    self.commit(&text);
                    KeyOutcome::Committed(text)
                } else {
                    KeyOutcome::Consumed
                }
            }
            '\u{8}' | '\u{7f}' => {
                // 退格
                self.buffer.pop();
                if self.buffer.is_empty() {
                    self.cancel();
                    KeyOutcome::Consumed
                } else {
                    self.recompute()
                }
            }
            '\u{1b}' => {
                // Esc
                self.cancel();
                KeyOutcome::Consumed
            }
            _ => KeyOutcome::PassThrough,
        }
    }

    /// 选择第 `index` 个候选并上屏，返回上屏文本。
    pub fn select(&mut self, index: usize) -> Option<String> {
        let text = self.candidates.get(index)?.text.clone();
        self.commit(&text);
        Some(text)
    }

    /// 取消当前组合。
    pub fn cancel(&mut self) {
        self.composing = false;
        self.buffer.clear();
        self.candidates.clear();
    }

    fn commit(&mut self, text: &str) {
        self.committed.clear();
        self.committed.push_str(text);
        self.cancel();
    }

    fn recompute(&mut self) -> KeyOutcome {
        let mut merged: Vec<Candidate> = Vec::new();
        let mut auto: Option<String> = None;

        for engine in self.active_engines() {
            let result = engine.convert(&self.buffer, 9);
            if result.should_commit.is_some() && auto.is_none() {
                auto = result.should_commit;
            }
            merged.extend(result.candidates);
        }

        // 去重：同 text 保留权重最高者；再按权重降序。
        merged.sort_by(|a, b| b.weight.cmp(&a.weight).then_with(|| a.text.cmp(&b.text)));
        let mut seen = std::collections::HashSet::new();
        merged.retain(|c| seen.insert(c.text.clone()));
        self.candidates = merged;

        if let Some(text) = auto {
            self.commit(&text);
            KeyOutcome::Committed(text)
        } else {
            KeyOutcome::Consumed
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct MockEngine;

    impl Engine for MockEngine {
        fn convert(&self, input: &str, _max: usize) -> ConvertResult {
            let mut candidates = Vec::new();
            if input.contains('a') {
                candidates.push(Candidate::new("甲", input, 10, CandidateSource::CodeTable));
            }
            if input.contains('b') {
                candidates.push(Candidate::new("乙", input, 9, CandidateSource::CodeTable));
            }
            ConvertResult {
                candidates,
                should_commit: None,
            }
        }

        fn engine_type(&self) -> EngineType {
            EngineType::CodeTable
        }

        fn max_code_length(&self) -> usize {
            4
        }
    }

    fn session_with_wubi(mode: InputMode) -> Session {
        let mut s = Session::new(mode);
        s.set_wubi_engine(Box::new(MockEngine));
        s
    }

    #[test]
    fn mode_cycle() {
        assert_eq!(InputMode::Mixed.next(), InputMode::WubiOnly);
        assert_eq!(InputMode::WubiOnly.next(), InputMode::PinyinOnly);
        assert_eq!(InputMode::PinyinOnly.next(), InputMode::Mixed);
    }

    #[test]
    fn mode_from_str() {
        assert_eq!("mixed".parse::<InputMode>(), Ok(InputMode::Mixed));
        assert!("nope".parse::<InputMode>().is_err());
    }

    #[test]
    fn typing_produces_candidates() {
        let mut s = session_with_wubi(InputMode::Mixed);
        assert_eq!(s.handle_key('a'), KeyOutcome::Consumed);
        assert!(s.composing());
        assert!(s.candidates().iter().any(|c| c.text == "甲"));
    }

    #[test]
    fn space_commits_first() {
        let mut s = session_with_wubi(InputMode::Mixed);
        s.handle_key('a');
        match s.handle_key(' ') {
            KeyOutcome::Committed(text) => assert_eq!(text, "甲"),
            other => panic!("expected commit, got {other:?}"),
        }
        assert!(!s.composing());
        assert_eq!(s.committed(), "甲");
    }

    #[test]
    fn digit_selects_candidate() {
        let mut s = session_with_wubi(InputMode::Mixed);
        s.handle_key('a');
        s.handle_key('b');
        match s.handle_key('2') {
            KeyOutcome::Committed(text) => assert_eq!(text, "乙"),
            other => panic!("expected commit, got {other:?}"),
        }
    }

    #[test]
    fn backspace_and_escape() {
        let mut s = session_with_wubi(InputMode::Mixed);
        s.handle_key('a');
        s.handle_key('b');
        assert_eq!(s.buffer(), "ab");
        s.handle_key('\u{8}');
        assert_eq!(s.buffer(), "a");
        s.handle_key('\u{8}');
        assert!(!s.composing());
        s.handle_key('x');
        s.handle_key('\u{1b}');
        assert!(!s.composing());
    }

    #[test]
    fn pinyin_mode_without_engine_yields_no_candidates() {
        let mut s = session_with_wubi(InputMode::PinyinOnly);
        assert_eq!(s.handle_key('a'), KeyOutcome::Consumed);
        assert!(s.candidates().is_empty());
    }
}
