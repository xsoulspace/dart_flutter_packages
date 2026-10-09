//! Byte-level BPE tokenizer (ADR 0054 R2 qwen, ADR 0055 LFM2 rung): a
//! hand-rolled GPT-2-style byte-level BPE, because the reference
//! `tokenizers` crate is not in the offline cargo registry. Two snapshot
//! layouts load: Qwen3's vocab.json + merges.txt (+ added tokens from
//! tokenizer.json), and tokenizer.json-embedded vocab/merges (LFM2.5).
//!
//! The pre-tokenizer implements the GPT-4-family alternation shared by both
//! checkpoints (checked against the snapshots at load parity time):
//!
//! ```text
//! (?i:'s|'t|'re|'ve|'m|'ll|'d)
//! | [^\r\n\p{L}\p{N}]?\p{L}+
//! | \p{N}{1,digit_run}      (qwen: 1, LFM2.5: 3)
//! |  ?[^\s\p{L}\p{N}]+[\r\n]*
//! | \s*[\r\n]+
//! | \s+(?!\S)
//! | \s+
//! ```
//!
//! implemented as an ordered-branch scanner (python-regex semantics:
//! leftmost alternative that matches wins, each branch greedy). The `\s+(?!\S)`
//! lookahead becomes "a whitespace run followed by whitespace-or-EOS matches
//! all but its last char" — the classic GPT-2 pretokenization rule.
//!
//! Known limits, recorded as non-claims: `char::is_alphabetic()` is the
//! derived Alphabetic property (a slight superset of `\p{L}`) and
//! `char::is_whitespace()` is the White_Space property (python `\s` also
//! takes \x1c–\x1f). Exotic characters may branch differently; the parity
//! fixtures probe the common branches. Qwen3 normalizes NFC (its
//! tokenizer.json normalizer); LFM2.5 declares no normalizer and is loaded
//! with normalization off.

use std::collections::HashMap;
use std::path::Path;

use unicode_normalization::UnicodeNormalization;

pub struct ByteLevelBpe {
    vocab: HashMap<String, u32>,
    id_to_token: Vec<String>,
    /// Byte-unicode space, rank = merge priority.
    merges: HashMap<(String, String), u32>,
    /// Added/special tokens: literal content → id (scanned longest-first).
    added: Vec<(String, u32)>,
    added_by_id: HashMap<u32, String>,
    byte_to_char: [char; 256],
    char_to_byte: HashMap<char, u8>,
    /// B3 digit-run length: `\p{N}{1,digit_run}` (qwen 1, LFM2.5 3).
    digit_run: usize,
    /// Qwen3's tokenizer.json declares the NFC normalizer; LFM2.5 declares
    /// none and must not normalize.
    normalize_nfc: bool,
}

/// Shared tail of both loaders: added tokens, byte tables, reverse vocab.
fn finish(
    vocab: HashMap<String, u32>,
    merges: HashMap<(String, String), u32>,
    added_list: &serde_json::Value,
    digit_run: usize,
    normalize_nfc: bool,
) -> ByteLevelBpe {
    let mut added: Vec<(String, u32)> = Vec::new();
    let mut added_by_id: HashMap<u32, String> = HashMap::new();
    if let Some(list) = added_list.get("added_tokens").and_then(|v| v.as_array()) {
        for t in list {
            let id = t.get("id").and_then(|v| v.as_u64()).unwrap_or_default() as u32;
            let content = t
                .get("content")
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string();
            if !content.is_empty() {
                added.push((content.clone(), id));
                added_by_id.insert(id, content);
            }
        }
    }
    // Longest-first so "<|im_start|>" wins over any prefix.
    added.sort_by(|a, b| b.0.chars().count().cmp(&a.0.chars().count()));

    let (byte_to_char, char_to_byte) = byte_unicode_tables();

    let mut max_id = 0usize;
    for id in vocab.values() {
        max_id = max_id.max(*id as usize);
    }
    let mut id_to_token = vec![String::new(); max_id + 1];
    for (tok, id) in &vocab {
        id_to_token[*id as usize] = tok.clone();
    }

    ByteLevelBpe {
        vocab,
        id_to_token,
        merges,
        added,
        added_by_id,
        byte_to_char,
        char_to_byte,
        digit_run,
        normalize_nfc,
    }
}

fn read_tokenizer_json(dir: &Path) -> Result<serde_json::Value, String> {
    serde_json::from_str(
        &std::fs::read_to_string(dir.join("tokenizer.json"))
            .map_err(|e| format!("tokenizer.json: {e}"))?,
    )
    .map_err(|e| format!("tokenizer.json parse: {e}"))
}

impl ByteLevelBpe {
    /// Loads a Qwen3 snapshot (vocab.json, merges.txt, tokenizer.json for
    /// the added-token list): single-digit pre-tokens, NFC normalization.
    pub fn load(dir: &Path) -> Result<ByteLevelBpe, String> {
        let vocab: HashMap<String, u32> = serde_json::from_str(
            &std::fs::read_to_string(dir.join("vocab.json"))
                .map_err(|e| format!("vocab.json: {e}"))?,
        )
        .map_err(|e| format!("vocab.json parse: {e}"))?;

        let mut merges = HashMap::new();
        let merges_txt = std::fs::read_to_string(dir.join("merges.txt"))
            .map_err(|e| format!("merges.txt: {e}"))?;
        let mut rank = 0u32;
        for line in merges_txt.lines() {
            if line.starts_with("#version") || line.trim().is_empty() {
                continue;
            }
            let mut parts = line.split_whitespace();
            let (a, b) = match (parts.next(), parts.next()) {
                (Some(a), Some(b)) => (a.to_string(), b.to_string()),
                _ => continue,
            };
            merges.insert((a, b), rank);
            rank += 1;
        }

        let tj = read_tokenizer_json(dir)?;
        Ok(finish(vocab, merges, &tj, 1, true))
    }

    /// Loads a snapshot that embeds vocab + merges inside tokenizer.json
    /// (LFM2.5): three-digit pre-token runs, no normalization.
    pub fn load_tokenizer_json(dir: &Path) -> Result<ByteLevelBpe, String> {
        let tj = read_tokenizer_json(dir)?;
        let model = tj
            .get("model")
            .ok_or_else(|| "tokenizer.json: no model".to_string())?;
        if model.get("type").and_then(|v| v.as_str()) != Some("BPE") {
            return Err(format!(
                "tokenizer.json model type {:?} is not BPE",
                model.get("type").and_then(|v| v.as_str())
            ));
        }
        let vocab: HashMap<String, u32> = serde_json::from_value(
            model
                .get("vocab")
                .cloned()
                .ok_or_else(|| "tokenizer.json: no vocab".to_string())?,
        )
        .map_err(|e| format!("tokenizer.json vocab: {e}"))?;

        let mut merges = HashMap::new();
        let raw = model
            .get("merges")
            .and_then(|v| v.as_array())
            .ok_or_else(|| "tokenizer.json: no merges".to_string())?;
        let mut rank = 0u32;
        for m in raw {
            let (a, b) = match m {
                serde_json::Value::String(s) => match s.split_once(' ') {
                    Some((a, b)) => (a.to_string(), b.to_string()),
                    None => continue,
                },
                serde_json::Value::Array(pair) if pair.len() == 2 => {
                    let (Some(a), Some(b)) = (pair[0].as_str(), pair[1].as_str()) else {
                        continue;
                    };
                    (a.to_string(), b.to_string())
                }
                _ => continue,
            };
            merges.insert((a, b), rank);
            rank += 1;
        }

        Ok(finish(vocab, merges, &tj, 3, false))
    }

    /// Text → token ids: normalize (when the checkpoint declares a
    /// normalizer), split on added tokens, pre-tokenize, byte-encode,
    /// BPE-merge, look up.
    pub fn encode(&self, text: &str) -> Result<Vec<u32>, String> {
        let normalized: String = if self.normalize_nfc {
            text.nfc().collect()
        } else {
            text.to_string()
        };
        let chars: Vec<char> = normalized.chars().collect();
        let mut out = Vec::new();
        let mut i = 0usize;
        while i < chars.len() {
            if let Some(id) = self.match_added(&chars[i..]) {
                out.push(id);
                i += self.added_content_len(&chars[i..]);
                continue;
            }
            let len = pretoken_len(&chars[i..], self.digit_run).ok_or_else(|| {
                format!("no pretokenizer branch matched at offset {i} of {text:?}")
            })?;
            let piece: String = chars[i..i + len].iter().collect();
            let bencoded: String = piece
                .as_bytes()
                .iter()
                .map(|&b| self.byte_to_char[b as usize])
                .collect();
            for tok in self.bpe(&bencoded) {
                let id = self
                    .vocab
                    .get(&tok)
                    .copied()
                    .ok_or_else(|| format!("bpe token {tok:?} not in vocab"))?;
                out.push(id);
            }
            i += len;
        }
        Ok(out)
    }

    /// Token ids → text (vocab pieces byte-decode; added tokens are literal).
    pub fn decode(&self, ids: &[u32]) -> Result<String, String> {
        let mut bytes = Vec::new();
        for &id in ids {
            if let Some(literal) = self.added_by_id.get(&id) {
                bytes.extend_from_slice(literal.as_bytes());
                continue;
            }
            let tok = self
                .id_to_token
                .get(id as usize)
                .and_then(|t| if t.is_empty() { None } else { Some(t) })
                .ok_or_else(|| format!("id {id} not in vocab"))?;
            for c in tok.chars() {
                let b = self
                    .char_to_byte
                    .get(&c)
                    .copied()
                    .ok_or_else(|| format!("token {tok:?} has non-byte char {c:?}"))?;
                bytes.push(b);
            }
        }
        Ok(String::from_utf8_lossy(&bytes).into_owned())
    }

    fn match_added(&self, at: &[char]) -> Option<u32> {
        for (content, id) in &self.added {
            let cch: Vec<char> = content.chars().collect();
            if at.len() >= cch.len() && at[..cch.len()] == cch[..] {
                return Some(*id);
            }
        }
        None
    }

    fn added_content_len(&self, at: &[char]) -> usize {
        // The just-matched content's char length (re-derives from `added`,
        // which match_added selected).
        for (content, _) in &self.added {
            let cch: Vec<char> = content.chars().collect();
            if at.len() >= cch.len() && at[..cch.len()] == cch[..] {
                return cch.len();
            }
        }
        0
    }

    /// Classic GPT-2 BPE: repeatedly merge the lowest-rank adjacent pair
    /// (leftmost occurrence first).
    fn bpe(&self, word: &str) -> Vec<String> {
        let mut parts: Vec<String> = word.chars().map(String::from).collect();
        loop {
            let mut best: Option<(u32, usize)> = None;
            for i in 1..parts.len() {
                if let Some(&r) = self.merges.get(&(parts[i - 1].clone(), parts[i].clone())) {
                    if best.is_none() || r < best.unwrap().0 {
                        best = Some((r, i));
                    }
                }
            }
            let Some((_, i)) = best else { break };
            let merged = format!("{}{}", parts[i - 1], parts[i]);
            parts[i - 1] = merged;
            parts.remove(i);
        }
        parts
    }
}

/// The GPT-2 bytes_to_unicode table: printable ASCII/Latin-1 ranges map to
/// themselves; the rest shift into the 256+ code point range.
fn byte_unicode_tables() -> ([char; 256], HashMap<char, u8>) {
    let mut bs: Vec<u8> = Vec::new();
    for b in 0x21..=0x7E {
        bs.push(b);
    }
    for b in 0xA1..=0xAC {
        bs.push(b);
    }
    for b in 0xAE..=0xFF {
        bs.push(b);
    }
    let mut cs: Vec<u32> = bs.iter().map(|&b| b as u32).collect();
    let mut n = 0u32;
    for b in 0..=255u8 {
        if !bs.contains(&b) {
            bs.push(b);
            cs.push(256 + n);
            n += 1;
        }
    }
    let mut byte_to_char = ['\0'; 256];
    let mut char_to_byte = HashMap::new();
    for (&b, &c) in bs.iter().zip(cs.iter()) {
        let ch = char::from_u32(c).unwrap();
        byte_to_char[b as usize] = ch;
        char_to_byte.insert(ch, b);
    }
    (byte_to_char, char_to_byte)
}

fn is_letter(c: char) -> bool {
    c.is_alphabetic()
}

fn is_number(c: char) -> bool {
    c.is_numeric()
}

fn is_space(c: char) -> bool {
    c.is_whitespace()
}

/// The length (in chars) of the pre-token match at the start of `at`, per
/// the ordered alternation. Every branch terminates, so the `None` case
/// means the input has a character outside all classes — treated as an
/// error by the caller. `digit_run` is B3's `\p{N}{1,digit_run}` bound.
fn pretoken_len(at: &[char], digit_run: usize) -> Option<usize> {
    let n = at.len();
    if n == 0 {
        return None;
    }

    // B1: (?i:'s|'t|'re|'ve|'m|'ll|'d) — try the listed order.
    if at[0] == '\'' {
        for suffix in ["s", "t", "re", "ve", "m", "ll", "d"] {
            let sch: Vec<char> = suffix.chars().collect();
            if n >= 1 + sch.len()
                && at[1..1 + sch.len()]
                    .iter()
                    .zip(sch.iter())
                    .all(|(a, b)| a.to_lowercase().eq(b.to_lowercase()))
            {
                return Some(1 + sch.len());
            }
        }
    }

    // B2: [^\r\n\p{L}\p{N}]?\p{L}+ — the optional char excludes only
    // \r, \n, letters, and digits (a tab or other whitespace still fits).
    {
        let optional = at[0] != '\r' && at[0] != '\n' && !is_letter(at[0]) && !is_number(at[0]);
        let base = if optional { 1 } else { 0 };
        let mut j = base;
        while j < n && is_letter(at[j]) {
            j += 1;
        }
        if j > base {
            return Some(j);
        }
        // With the optional char consumed but no letters after it, the
        // branch cannot restart without it (at[0] is not a letter by the
        // optional-class membership), so B2 fails here.
    }

    // B3: \p{N}{1,digit_run} — up to digit_run digits per pre-token
    // (greedy, so a shorter trailing run matches whatever remains).
    if is_number(at[0]) {
        let mut j = 0usize;
        while j < n && j < digit_run && is_number(at[j]) {
            j += 1;
        }
        return Some(j);
    }

    // B4:  ?[^\s\p{L}\p{N}]+[\r\n]*
    {
        let mut j = if at[0] == ' ' { 1 } else { 0 };
        let punct_start = j;
        while j < n && !is_space(at[j]) && !is_letter(at[j]) && !is_number(at[j]) {
            j += 1;
        }
        if j > punct_start {
            while j < n && (at[j] == '\r' || at[j] == '\n') {
                j += 1;
            }
            return Some(j);
        }
    }

    // B5: \s*[\r\n]+ — the whitespace run up to (and including) the LAST
    // consecutive \r\n run inside it.
    {
        let mut j = 0usize;
        while j < n && is_space(at[j]) {
            j += 1;
        }
        // Find the end of the last maximal \r\n run in [0, j).
        let mut t = None;
        let mut k = 0usize;
        while k < j {
            if at[k] == '\r' || at[k] == '\n' {
                let mut e = k;
                while e < j && (at[e] == '\r' || at[e] == '\n') {
                    e += 1;
                }
                t = Some(e);
                k = e;
            } else {
                k += 1;
            }
        }
        if let Some(t) = t {
            if t > 0 {
                return Some(t);
            }
        }
    }

    // B6: \s+(?!\S) — a whitespace run followed by whitespace-or-EOS matches
    // all but its last char (greedy backtracking over the lookahead).
    {
        let mut j = 0usize;
        while j < n && is_space(at[j]) {
            j += 1;
        }
        if j == n {
            return Some(j);
        }
        if j >= 2 {
            return Some(j - 1);
        }
    }

    // B7: \s+
    {
        let mut j = 0usize;
        while j < n && is_space(at[j]) {
            j += 1;
        }
        if j > 0 {
            return Some(j);
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tables() -> ByteLevelBpe {
        // Minimal hand-built tokenizer for scanner/table unit tests (no
        // model files needed).
        let (byte_to_char, char_to_byte) = byte_unicode_tables();
        ByteLevelBpe {
            vocab: HashMap::new(),
            id_to_token: Vec::new(),
            merges: HashMap::new(),
            added: vec![("<|im_start|>".to_string(), 151644)],
            added_by_id: HashMap::from([(
                151644u32,
                "<|im_start|>".to_string(),
            )]),
            byte_to_char,
            char_to_byte,
            digit_run: 1,
            normalize_nfc: true,
        }
    }

    #[test]
    fn byte_tables_round_trip() {
        let (b2c, c2b) = byte_unicode_tables();
        for b in 0..=255u8 {
            assert_eq!(c2b[&b2c[b as usize]], b);
        }
        // GPT-2 anchors.
        assert_eq!(b2c[b' ' as usize], 'Ġ');
        assert_eq!(b2c[b'\n' as usize], 'Ċ');
        assert_eq!(c2b[&'Ġ'], b' ');
    }

    #[test]
    fn pretokenizer_branches() {
        let f = |s: &str| pretoken_len(&s.chars().collect::<Vec<_>>(), 1);
        assert_eq!(f("  leading"), Some(1)); // B6 leaves " leading" intact
        assert_eq!(f(" leading"), Some(8)); // B2 space + letters
        assert_eq!(f("12345"), Some(1)); // B3 single digit (qwen)
        assert_eq!(f("(x)"), Some(2)); // B2 optional punct + letters "(x"
        assert_eq!(f("(!)"), Some(3)); // B4 punct run swallows all
        assert_eq!(f("abc(x"), Some(3)); // B2 letters
        assert_eq!(f("it's"), Some(2)); // B2 "it"
        assert_eq!(f("'s"), Some(2)); // B1
        assert_eq!(f("'VE"), Some(3)); // B1 case-insensitive 've
        assert_eq!(f("\n\nx"), Some(2)); // B5 both newlines
        assert_eq!(f(" \n ab"), Some(2)); // B5 " \n" (leaves " ab")
        assert_eq!(f("   "), Some(3)); // B6 run to EOS
        assert_eq!(f(" a"), Some(2)); // B2 space+letters wins over B6
        assert_eq!(f(" 1"), Some(1)); // B7 lone space (digit next)
    }

    #[test]
    fn digit_run_three() {
        // LFM2.5's \p{N}{1,3}: greedy three-digit runs.
        let f3 = |s: &str| pretoken_len(&s.chars().collect::<Vec<_>>(), 3);
        assert_eq!(f3("12345"), Some(3)); // "123", then "45"
        assert_eq!(f3("12x"), Some(2)); // short trailing run
        assert_eq!(f3("1"), Some(1));
        assert_eq!(f3("123"), Some(3));
    }

    #[test]
    fn added_tokens_split_first() {
        let t = tables();
        // The mini vocab only holds the added token; surrounding letters
        // would fail lookup, so probe the added token alone.
        let ids = t.encode("<|im_start|>").unwrap();
        assert_eq!(ids, vec![151644]);
        assert_eq!(t.decode(&[151644]).unwrap(), "<|im_start|>");
    }
}
