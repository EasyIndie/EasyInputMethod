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
    /// A spelling approximation; exact matches rank first within the source.
    pub is_fuzzy: bool,
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
            is_fuzzy: false,
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
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

/// 组合缓冲区字符数硬上限（ADR-062）。
///
/// 覆盖所有引擎的合法码长：五笔 4、拼音 32、用户词库编码 64（ADR-029）。
/// 达到上限后忽略后续字母键，避免长串触发超线性代价。
pub const MAX_COMPOSE_LEN: usize = 64;

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
    engine_options: Option<EngineOptions>,
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
        self.engine_options = None;
    }

    pub fn set_pinyin_engine(&mut self, engine: Box<dyn Engine>) {
        self.pinyin = Some(engine);
        self.engine_options = None;
    }

    pub fn set_input_options(&mut self, full_width: bool, chinese_punctuation: bool) {
        if self.full_width != full_width {
            self.width_override = None;
        }
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

    /// 当前是否全角（含临时切换覆盖）。
    pub fn is_full_width(&self) -> bool {
        self.width_override.unwrap_or(self.full_width)
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

    /// Apply changed engine options and refresh composition without committing it.
    pub fn configure_engines(&mut self, options: &EngineOptions) -> bool {
        if self.engine_options.as_ref() == Some(options) {
            return false;
        }
        self.engine_options = Some(*options);
        if let Some(engine) = self.wubi.as_mut() {
            engine.configure(options);
        }
        if let Some(engine) = self.pinyin.as_mut() {
            engine.configure(options);
        }
        if self.composing {
            self.recompute_with_commit(false);
        }
        true
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
            self.arrange_mixed_fallback();
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
                .then_with(|| a.is_fuzzy.cmp(&b.is_fuzzy))
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
        self.arrange_mixed_fallback();
        self.page = self.page.min(self.page_count().saturating_sub(1));
    }

    fn arrange_mixed_fallback(&mut self) {
        if self.mode != InputMode::Mixed {
            return;
        }
        // Stable source partition preserves each engine's learned ordering.
        self.candidates
            .sort_by_key(|c| c.source == CandidateSource::Pinyin);
        let table_count = self
            .candidates
            .iter()
            .take_while(|c| c.source != CandidateSource::Pinyin)
            .count();
        if table_count == 0 {
            return;
        }
        let eligible: Vec<_> = self
            .candidates
            .iter()
            .enumerate()
            .filter(|(_, c)| c.source == CandidateSource::Pinyin && !c.is_fuzzy)
            .take(2)
            .map(|(index, _)| index)
            .collect();
        if eligible.is_empty() {
            return;
        }
        let insertion = table_count.min(self.page_size - eligible.len());
        let mut fallback = Vec::new();
        for index in eligible.into_iter().rev() {
            fallback.push(self.candidates.remove(index));
        }
        fallback.reverse();
        self.candidates.splice(insertion..insertion, fallback);
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
                // 达上限后忽略字母（ADR-062）：不改缓冲、不误上屏。
                if self.buffer.len() >= MAX_COMPOSE_LEN {
                    return KeyOutcome::Consumed;
                }
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
        self.recompute_with_commit(true)
    }

    fn recompute_with_commit(&mut self, allow_commit: bool) -> KeyOutcome {
        let mut merged: Vec<Candidate> = Vec::new();
        let mut auto: Option<String> = None;

        for engine in self.active_engines() {
            // 引擎只处理不超过其声明码长的输入（五笔 4 / 拼音 32），避免长码无用功（ADR-062）。
            if self.buffer.len() > engine.max_code_length() {
                continue;
            }
            let result = engine.convert(&self.buffer, 256);
            if result.should_commit.is_some() && auto.is_none() {
                auto = result.should_commit;
            }
            merged.extend(result.candidates);
        }

        // Deduplicate by source priority, exact spelling and then frequency.
        // Check before deduplication: a pinyin alternative may share text with
        // another table candidate and lose its source during the merge.
        let auto = auto.filter(|text| {
            self.mode != InputMode::Mixed
                || !merged.iter().any(|candidate| {
                    candidate.source == CandidateSource::Pinyin && candidate.text != *text
                })
        });
        merged.sort_by(|a, b| {
            usize::from(a.source == CandidateSource::Pinyin)
                .cmp(&usize::from(b.source == CandidateSource::Pinyin))
                .then_with(|| a.is_fuzzy.cmp(&b.is_fuzzy))
                .then_with(|| b.weight.cmp(&a.weight))
                .then_with(|| a.text.cmp(&b.text))
        });
        let mut seen = std::collections::HashSet::new();
        merged.retain(|c| seen.insert(c.text.clone()));
        self.candidates = merged;
        self.arrange_mixed_fallback();
        self.page = 0;

        if let Some(text) = auto.filter(|_| allow_commit) {
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

    struct AutoConflictEngine(EngineType, &'static str);
    impl Engine for AutoConflictEngine {
        fn convert(&self, input: &str, _: usize) -> ConvertResult {
            if input != "wang" {
                return ConvertResult::default();
            }
            let source = if self.0 == EngineType::Pinyin {
                CandidateSource::Pinyin
            } else {
                CandidateSource::CodeTable
            };
            ConvertResult {
                candidates: vec![Candidate::new(self.1, input, 10, source)],
                should_commit: if self.0 == EngineType::CodeTable {
                    Some(self.1.into())
                } else {
                    None
                },
            }
        }
        fn engine_type(&self) -> EngineType {
            self.0
        }
        fn max_code_length(&self) -> usize {
            32
        }
    }

    #[test]
    fn mixed_auto_commit_waits_for_distinct_pinyin_and_allows_explicit_choice() {
        for key in ['1', '2', ' ', '\u{1b}', '\u{8}', 'a'] {
            let mut s = Session::new(InputMode::Mixed);
            s.set_wubi_engine(Box::new(AutoConflictEngine(EngineType::CodeTable, "佢")));
            s.set_pinyin_engine(Box::new(AutoConflictEngine(EngineType::Pinyin, "王")));
            for ch in "wang".chars() {
                assert_eq!(s.handle_key(ch), KeyOutcome::Consumed);
            }
            assert_eq!(s.buffer(), "wang");
            assert_eq!(s.committed(), "");
            let result = s.handle_key(key);
            match key {
                '1' | ' ' => assert_eq!(result, KeyOutcome::Committed("佢".into())),
                '2' => assert_eq!(result, KeyOutcome::Committed("王".into())),
                '\u{1b}' => assert_eq!(s.buffer(), ""),
                '\u{8}' => assert_eq!(s.buffer(), "wan"),
                _ => assert_eq!(s.buffer(), "wanga"),
            }
        }
    }

    #[test]
    fn pure_wubi_and_same_text_mixed_keep_unique_auto_commit() {
        for mode in [InputMode::WubiOnly, InputMode::Mixed] {
            let mut s = Session::new(mode);
            s.set_wubi_engine(Box::new(AutoConflictEngine(EngineType::CodeTable, "佢")));
            s.set_pinyin_engine(Box::new(AutoConflictEngine(
                EngineType::Pinyin,
                if mode == InputMode::Mixed {
                    "佢"
                } else {
                    "王"
                },
            )));
            for ch in "wan".chars() {
                s.handle_key(ch);
            }
            assert_eq!(s.handle_key('g'), KeyOutcome::Committed("佢".into()));
        }
    }

    #[test]
    fn mixed_fallback_stays_visible_after_learning_and_page_size_changes() {
        let mut s = Session::new(InputMode::Mixed);
        s.set_wubi_engine(Box::new(ManyEngine));
        s.handle_key('a');
        let pin = |text: &str, weight| Candidate::new(text, "a", weight, CandidateSource::Pinyin);
        let mut fuzzy = pin("模糊", 1000);
        fuzzy.is_fuzzy = true;
        s.personalize(vec![pin("拼一", 20), pin("拼二", 10), fuzzy], |_| 0);
        assert_eq!(s.candidates()[0].text, "词00");
        assert_eq!(s.candidates()[7].text, "拼一");
        assert_eq!(s.candidates()[8].text, "拼二");
        assert_eq!(s.candidates.len(), 23);
        s.personalize(vec![], |c| if c.text == "词19" { 100 } else { 0 });
        assert_eq!(s.candidates()[0].text, "词19");
        assert_eq!(s.candidates()[7].text, "拼一");
        s.page(1);
        assert_eq!(s.candidates()[0].text, "词06");
        s.set_page_size(3);
        assert_eq!(s.candidates()[0].text, "词19");
        assert_eq!(s.candidates()[1].text, "拼一");
        assert_eq!(s.candidates()[2].text, "拼二");
        assert_eq!(s.handle_key('2'), KeyOutcome::Committed("拼一".into()));
    }

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

    struct ChangingEngine(bool);
    impl Engine for ChangingEngine {
        fn configure(&mut self, options: &EngineOptions) {
            self.0 = options.fuzzy;
        }
        fn convert(&self, input: &str, _max: usize) -> ConvertResult {
            ConvertResult {
                candidates: (0..20)
                    .map(|i| {
                        Candidate::new(
                            format!("{}-{i:02}", if self.0 { "new" } else { "old" }),
                            input,
                            100 - i,
                            CandidateSource::Pinyin,
                        )
                    })
                    .collect(),
                should_commit: if self.0 {
                    Some("must-not-commit-on-config".into())
                } else {
                    None
                },
            }
        }
        fn engine_type(&self) -> EngineType {
            EngineType::Pinyin
        }
        fn max_code_length(&self) -> usize {
            32
        }
    }

    #[test]
    fn engine_option_changes_recompute_without_commit_and_duplicates_preserve_page() {
        let mut first = Session::new(InputMode::PinyinOnly);
        let mut second = Session::new(InputMode::PinyinOnly);
        let mut options = EngineOptions {
            auto_commit: false,
            z_wildcard: true,
            fuzzy: false,
        };
        for session in [&mut first, &mut second] {
            session.set_pinyin_engine(Box::new(ChangingEngine(false)));
            session.configure_engines(&options);
            session.handle_key('a');
            session.page(1);
        }
        assert_eq!(first.page_index(), 1);
        assert!(!first.configure_engines(&options));
        assert_eq!(first.page_index(), 1);
        options.fuzzy = true;
        assert!(first.configure_engines(&options));
        assert_eq!(first.buffer(), "a");
        assert!(first.composing());
        assert_eq!(first.committed(), "");
        assert_eq!(first.page_index(), 0);
        assert_eq!(first.candidates()[0].text, "new-00");
        assert_eq!(second.candidates()[0].text, "old-09");
        second.configure_engines(&options);
        assert_eq!(second.candidates()[0].text, "new-00");
        first.page(1);
        assert!(!first.configure_engines(&options));
        assert_eq!(first.page_index(), 1);
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
    fn personalization_keeps_exact_pinyin_before_fuzzy_even_with_maximal_learning() {
        let mut session = Session::new(InputMode::PinyinOnly);
        let exact = Candidate::new("张", "zhang", 9, CandidateSource::Pinyin);
        let mut fuzzy = Candidate::new("脏", "zang", i32::MAX, CandidateSource::Pinyin);
        fuzzy.is_fuzzy = true;
        session.personalize(
            vec![fuzzy, exact],
            |c| if c.is_fuzzy { u32::MAX } else { 0 },
        );
        assert_eq!(session.candidates()[0].text, "张");
        assert_eq!(session.candidates()[1].text, "脏");
    }

    #[test]
    fn compose_buffer_is_bounded_and_backspace_recovers() {
        let mut s = session_with_wubi(InputMode::WubiOnly);
        for _ in 0..MAX_COMPOSE_LEN {
            assert_eq!(s.handle_key('a'), KeyOutcome::Consumed);
        }
        assert_eq!(s.buffer().len(), MAX_COMPOSE_LEN);
        // 超限字母被忽略：不改变组合、不误上屏。
        assert_eq!(s.handle_key('b'), KeyOutcome::Consumed);
        assert_eq!(s.buffer().len(), MAX_COMPOSE_LEN);
        assert_eq!(s.committed(), "");
        // 退格后恢复可输入。
        assert_eq!(s.handle_key('\u{7f}'), KeyOutcome::Consumed);
        assert_eq!(s.buffer().len(), MAX_COMPOSE_LEN - 1);
        s.handle_key('b');
        assert_eq!(s.buffer().len(), MAX_COMPOSE_LEN);
    }

    #[test]
    fn engines_are_skipped_beyond_declared_code_length() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        use std::sync::Arc;

        struct CountingEngine(Arc<AtomicUsize>);
        impl Engine for CountingEngine {
            fn convert(&self, input: &str, _max: usize) -> ConvertResult {
                self.0.fetch_add(1, Ordering::SeqCst);
                ConvertResult {
                    candidates: vec![Candidate::new("甲", input, 1, CandidateSource::CodeTable)],
                    should_commit: None,
                }
            }
            fn engine_type(&self) -> EngineType {
                EngineType::CodeTable
            }
            fn max_code_length(&self) -> usize {
                2
            }
        }

        let calls = Arc::new(AtomicUsize::new(0));
        let mut s = Session::new(InputMode::WubiOnly);
        s.set_wubi_engine(Box::new(CountingEngine(Arc::clone(&calls))));
        s.handle_key('a');
        s.handle_key('b');
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        // 超出引擎声明码长后不再调用引擎（ADR-062）。
        s.handle_key('c');
        s.handle_key('d');
        assert_eq!(calls.load(Ordering::SeqCst), 2);
        assert_eq!(s.buffer(), "abcd");
        assert!(s.candidates().is_empty());
    }

    #[test]
    fn full_width_reflects_options_and_override() {
        let mut s = Session::new(InputMode::Mixed);
        s.set_input_options(false, false);
        assert!(!s.is_full_width());
        s.toggle_width();
        assert!(s.is_full_width());
        s.set_input_options(false, false);
        assert!(
            s.is_full_width(),
            "unchanged configure preserves temporary toggle"
        );
        s.set_input_options(true, false);
        assert!(s.is_full_width());
        s.set_input_options(false, false);
        assert!(!s.is_full_width());
        assert_eq!(s.handle_key('1'), KeyOutcome::PassThrough);
        s.toggle_english();
        s.set_input_options(true, false);
        assert!(s.english());
        assert_eq!(s.handle_key('1'), KeyOutcome::Committed("１".into()));
    }

    #[test]
    fn width_preference_does_not_cancel_composition_or_change_other_state() {
        let mut s = session_with_wubi(InputMode::Mixed);
        s.set_input_options(false, true);
        s.handle_key('a');
        let candidates = s.candidates().to_vec();
        s.set_input_options(true, true);
        assert_eq!(s.buffer(), "a");
        assert_eq!(s.candidates(), candidates);
        assert!(s.composing());
        assert!(!s.english());
        assert_eq!(s.mode(), InputMode::Mixed);
        assert_eq!(s.handle_key(','), KeyOutcome::Committed("甲，".into()));
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
