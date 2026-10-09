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
pub struct EngineOptions {
    pub auto_commit: bool,
    pub z_wildcard: bool,
    pub fuzzy: bool,
}

pub trait Engine: Send {
    fn configure(&mut self, _options: &EngineOptions) {}
    /// Return the preferred reading when reverse lookup is supported.
    fn reverse_lookup(&self, _text: &str) -> Option<String> {
        None
    }
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
    page: usize,
    page_size: usize,
    english: bool,
    full_width: bool,
    width_override: Option<bool>,
    chinese_punctuation: bool,
    double_quote_open: bool,
    single_quote_open: bool,
}

impl Session {
    pub fn new(mode: InputMode) -> Self {
        Self {
            mode,
            page_size: 9,
            ..Self::default()
        }
    }

    pub fn set_wubi_engine(&mut self, engine: Box<dyn Engine>) {
        self.wubi = Some(engine);
    }

    pub fn set_pinyin_engine(&mut self, engine: Box<dyn Engine>) {
        self.pinyin = Some(engine);
    }

    pub fn set_input_options(&mut self, full_width: bool, chinese_punctuation: bool) {
        self.full_width = full_width;
        self.chinese_punctuation = chinese_punctuation;
    }
    pub fn english(&self) -> bool {
        self.english
    }
    pub fn toggle_english(&mut self) {
        self.english = !self.english;
        self.cancel();
    }
    pub fn toggle_width(&mut self) {
        self.width_override = Some(!self.width_override.unwrap_or(self.full_width));
        self.cancel();
    }
    fn translate(&mut self, key: char) -> Option<String> {
        if !self.english && self.chinese_punctuation {
            let mapped = match key {
                '.' => Some('。'),
                ',' => Some('，'),
                '?' => Some('？'),
                '!' => Some('！'),
                ':' => Some('：'),
                ';' => Some('；'),
                '(' => Some('（'),
                ')' => Some('）'),
                '[' => Some('「'),
                ']' => Some('」'),
                '<' => Some('《'),
                '>' => Some('》'),
                '\\' => Some('、'),
                '"' => {
                    self.double_quote_open = !self.double_quote_open;
                    Some(if self.double_quote_open { '“' } else { '”' })
                }
                '\'' => {
                    self.single_quote_open = !self.single_quote_open;
                    Some(if self.single_quote_open { '‘' } else { '’' })
                }
                _ => None,
            };
            if let Some(value) = mapped {
                return Some(value.to_string());
            }
        }
        if self.width_override.unwrap_or(self.full_width) {
            if key == ' ' {
                return Some("　".into());
            }
            if ('!'..='~').contains(&key) {
                return char::from_u32(key as u32 + 0xfee0).map(|c| c.to_string());
            }
        }
        None
    }

    /// Query the installed reading engine without changing composition.
    pub fn reverse_lookup(&self, text: &str) -> Option<String> {
        self.pinyin.as_ref()?.reverse_lookup(text)
    }

    pub fn configure_engines(&mut self, options: &EngineOptions) {
        if let Some(engine) = self.wubi.as_mut() {
            engine.configure(options);
        }
        if let Some(engine) = self.pinyin.as_mut() {
            engine.configure(options);
        }
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
        let size = self.page_size.max(1);
        let start = (self.page * size).min(self.candidates.len());
        &self.candidates[start..(start + size).min(self.candidates.len())]
    }

    /// Set page length without changing the composition.
    pub fn set_page_size(&mut self, size: usize) {
        let size = size.clamp(3, 9);
        if self.page_size != size {
            self.page_size = size;
            self.page = 0;
        }
    }

    /// Merge local user entries and rank within each engine source.
    pub fn personalize(&mut self, extra: Vec<Candidate>, score: impl Fn(&Candidate) -> u32) {
        self.candidates.extend(extra);
        let mut scored: Vec<_> = self
            .candidates
            .drain(..)
            .map(|c| {
                let frequency = score(&c);
                (c, frequency)
            })
            .collect();
        let rank = |c: &Candidate| usize::from(c.source == CandidateSource::Pinyin);
        scored.sort_by(|(a, a_score), (b, b_score)| {
            rank(a)
                .cmp(&rank(b))
                .then_with(|| a.is_prefix.cmp(&b.is_prefix))
                .then_with(|| b_score.cmp(a_score))
                .then_with(|| b.weight.cmp(&a.weight))
                .then_with(|| a.text.cmp(&b.text))
        });
        let mut seen = std::collections::HashSet::new();
        self.candidates = scored
            .into_iter()
            .map(|(c, _)| c)
            .filter(|c| seen.insert(c.text.clone()))
            .collect();
        self.page = self.page.min(self.page_count().saturating_sub(1));
    }

    pub fn page_index(&self) -> usize {
        self.page
    }

    pub fn page_count(&self) -> usize {
        self.candidates.len().div_ceil(self.page_size.max(1))
    }

    pub fn page(&mut self, delta: i32) {
        self.page = (self.page as i64 + i64::from(delta))
            .clamp(0, self.page_count().saturating_sub(1) as i64) as usize;
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
        if self.english {
            if let Some(text) = self.translate(key) {
                self.commit(&text);
                return KeyOutcome::Committed(text);
            }
            return KeyOutcome::PassThrough;
        }
        if !self.composing {
            if key.is_ascii_lowercase() {
                self.composing = true;
                self.buffer.clear();
                self.buffer.push(key);
                return self.recompute();
            }
            if let Some(text) = self.translate(key) {
                self.commit(&text);
                return KeyOutcome::Committed(text);
            }
            return KeyOutcome::PassThrough;
        }

        match key {
            'a'..='z' => {
                self.buffer.push(key);
                self.recompute()
            }
            ' ' => {
                if let Some(first) = self.candidates().first() {
                    let text = first.text.clone();
                    self.commit(&text);
                    KeyOutcome::Committed(text)
                } else {
                    let text = self.buffer.clone();
                    self.commit(&text);
                    KeyOutcome::Committed(text)
                }
            }
            '\r' | '\n' => {
                let text = self.buffer.clone();
                self.commit(&text);
                KeyOutcome::Committed(text)
            }
            '1'..='9' => {
                let idx = (key as u8 - b'1') as usize;
                if let Some(c) = self.candidates().get(idx) {
                    let text = c.text.clone();
                    self.commit(&text);
                    KeyOutcome::Committed(text)
                } else {
                    KeyOutcome::Consumed
                }
            }
            '-' | '+' | '=' => {
                self.page(if key == '-' { -1 } else { 1 });
                KeyOutcome::Consumed
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
            _ => {
                if let Some(punctuation) = self.translate(key) {
                    let text = format!(
                        "{}{}",
                        self.candidates()
                            .first()
                            .map(|c| c.text.as_str())
                            .unwrap_or(&self.buffer),
                        punctuation
                    );
                    self.commit(&text);
                    KeyOutcome::Committed(text)
                } else {
                    KeyOutcome::PassThrough
                }
            }
        }
    }

    /// 选择第 `index` 个候选并上屏，返回上屏文本。
    pub fn select(&mut self, index: usize) -> Option<String> {
        let text = self.candidates().get(index)?.text.clone();
        self.commit(&text);
        Some(text)
    }

    /// End an input context while retaining its mode and transient preferences.
    pub fn focus_out(&mut self) {
        self.cancel();
        self.double_quote_open = false;
        self.single_quote_open = false;
    }

    /// 取消当前组合。
    pub fn cancel(&mut self) {
        self.composing = false;
        self.buffer.clear();
        self.candidates.clear();
        self.page = 0;
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
            let result = engine.convert(&self.buffer, 256);
            if result.should_commit.is_some() && auto.is_none() {
                auto = result.should_commit;
            }
            merged.extend(result.candidates);
        }

        // 去重：同 text 保留权重最高者；再按权重降序。
        merged.sort_by(|a, b| {
            usize::from(a.source == CandidateSource::Pinyin)
                .cmp(&usize::from(b.source == CandidateSource::Pinyin))
                .then_with(|| b.weight.cmp(&a.weight))
                .then_with(|| a.text.cmp(&b.text))
        });
        let mut seen = std::collections::HashSet::new();
        merged.retain(|c| seen.insert(c.text.clone()));
        self.candidates = merged;
        self.page = 0;

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

    struct ManyEngine;
    impl Engine for ManyEngine {
        fn convert(&self, input: &str, max: usize) -> ConvertResult {
            ConvertResult {
                candidates: (0..20)
                    .take(max)
                    .map(|i| {
                        Candidate::new(
                            format!("词{i:02}"),
                            input,
                            100 - i,
                            CandidateSource::CodeTable,
                        )
                    })
                    .collect(),
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

    #[test]
    fn return_commits_raw_composition_and_passes_through_when_idle() {
        for key in ['\r', '\n'] {
            let mut s = session_with_wubi(InputMode::Mixed);
            assert_eq!(s.handle_key(key), KeyOutcome::PassThrough);
            s.handle_key('a');
            assert_eq!(s.handle_key(key), KeyOutcome::Committed("a".into()));
            assert_eq!(s.committed(), "a");
            assert!(s.buffer().is_empty());
            assert!(s.candidates().is_empty());
            assert_eq!(s.handle_key(key), KeyOutcome::PassThrough);
        }
    }

    #[test]
    fn pagination_selects_visible_candidates_and_resets_on_edit() {
        let mut s = Session::new(InputMode::WubiOnly);
        s.set_wubi_engine(Box::new(ManyEngine));
        s.set_page_size(7);
        s.handle_key('a');
        assert_eq!(s.page_count(), 3);
        s.page(-1);
        assert_eq!(s.page_index(), 0);
        s.page(1);
        assert_eq!(s.candidates()[0].text, "词07");
        assert_eq!(s.handle_key('2'), KeyOutcome::Committed("词08".into()));
        s.handle_key('a');
        s.page(i32::MAX);
        assert_eq!(s.page_index(), 2);
        assert_eq!(s.candidates().len(), 6);
        s.handle_key('b');
        assert_eq!(s.page_index(), 0);
        s.page(1);
        s.handle_key('\u{7f}');
        assert_eq!(s.page_index(), 0);
        s.page(1);
        s.set_page_size(3);
        assert_eq!(s.page_index(), 0);
        assert_eq!(s.page_count(), 7);
        s.page(1);
        assert_eq!(s.select(0), Some("词03".into()));
        assert_eq!(s.page_count(), 0);
    }

    #[test]
    fn punctuation_quotes_width_and_english_are_session_state() {
        let mut s = session_with_wubi(InputMode::Mixed);
        s.set_input_options(false, true);
        s.handle_key('a');
        assert_eq!(s.handle_key(','), KeyOutcome::Committed("甲，".into()));
        assert_eq!(s.handle_key('"'), KeyOutcome::Committed("“".into()));
        assert_eq!(s.handle_key('"'), KeyOutcome::Committed("”".into()));
        s.toggle_english();
        assert_eq!(s.handle_key('a'), KeyOutcome::PassThrough);
        assert_eq!(s.handle_key('.'), KeyOutcome::PassThrough);
        s.toggle_width();
        assert_eq!(s.handle_key('A'), KeyOutcome::Committed("Ａ".into()));
        assert_eq!(s.handle_key(' '), KeyOutcome::Committed("　".into()));
        s.toggle_width();
        s.toggle_english();
        s.handle_key('x');
        assert_eq!(s.handle_key(' '), KeyOutcome::Committed("x".into()));
    }

    #[test]
    fn focus_out_resets_quotes_without_resetting_mode_or_width() {
        let mut s = session_with_wubi(InputMode::WubiOnly);
        s.set_input_options(false, true);
        assert_eq!(s.handle_key('"'), KeyOutcome::Committed("“".into()));
        s.cancel();
        assert_eq!(s.handle_key('"'), KeyOutcome::Committed("”".into()));
        assert_eq!(s.handle_key('\''), KeyOutcome::Committed("‘".into()));
        s.handle_key('a');
        s.focus_out();
        assert!(!s.composing());
        assert!(s.buffer().is_empty());
        assert_eq!(s.mode(), InputMode::WubiOnly);
        assert_eq!(s.handle_key('\''), KeyOutcome::Committed("‘".into()));
        assert_eq!(s.handle_key('"'), KeyOutcome::Committed("“".into()));
        s.toggle_english();
        s.toggle_width();
        s.focus_out();
        assert!(s.english());
        assert_eq!(s.handle_key('A'), KeyOutcome::Committed("Ａ".into()));
    }

    #[test]
    fn personalization_evaluates_each_frequency_once() {
        use std::cell::Cell;
        let mut s = session_with_wubi(InputMode::Mixed);
        s.handle_key('a');
        let original = s.candidates.len();
        let extra = vec![Candidate::new("新增", "a", 0, CandidateSource::CodeTable)];
        let calls = Cell::new(0);
        s.personalize(extra, |c| {
            calls.set(calls.get() + 1);
            u32::from(c.text == "新增")
        });
        assert_eq!(calls.get(), original + 1);
        assert_eq!(s.candidates[0].text, "新增");
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
