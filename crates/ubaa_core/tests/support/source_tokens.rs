//! 源码架构测试使用的轻量 Rust token 扫描工具。

use std::path::{Path, PathBuf};

/// 递归收集目录中的 Rust 源文件，并按路径稳定排序。
///
/// # Panics
///
/// 目录或目录项无法读取时 panic。
#[must_use]
pub fn rust_files_below(root: &Path) -> Vec<PathBuf> {
    fn visit(directory: &Path, files: &mut Vec<PathBuf>) {
        let entries = std::fs::read_dir(directory)
            .unwrap_or_else(|error| panic!("读取 {}: {error}", directory.display()));
        for entry in entries {
            let entry = entry
                .unwrap_or_else(|error| panic!("读取 {} 的目录项: {error}", directory.display()));
            let path = entry.path();
            let file_type = entry
                .file_type()
                .unwrap_or_else(|error| panic!("读取 {} 的文件类型: {error}", path.display()));
            if file_type.is_dir() {
                visit(&path, files);
            } else if file_type.is_file() && path.extension() == Some(std::ffi::OsStr::new("rs")) {
                files.push(path);
            }
        }
    }

    let mut files = Vec::new();
    visit(root, &mut files);
    files.sort();
    files
}

/// 忽略注释、字面量和空白，将 Rust 源码拆成标识符与标点 token。
#[must_use]
pub fn rust_tokens(source: &str) -> Vec<String> {
    tokenize(source, false)
}

/// 保留字面量原文，供架构门禁解析 `path` 属性；注释与空白仍被忽略。
#[must_use]
pub fn rust_tokens_with_literals(source: &str) -> Vec<String> {
    tokenize(source, true)
}

fn tokenize(source: &str, keep_literals: bool) -> Vec<String> {
    let bytes = source.as_bytes();
    let mut tokens = Vec::new();
    let mut cursor = 0;

    while cursor < bytes.len() {
        let character = source[cursor..]
            .chars()
            .next()
            .expect("cursor 始终位于源码字符边界");
        if character.is_whitespace() {
            cursor += character.len_utf8();
            continue;
        }
        if bytes[cursor..].starts_with(b"//") {
            cursor = line_comment_end(bytes, cursor + 2);
            continue;
        }
        if bytes[cursor..].starts_with(b"/*") {
            cursor = block_comment_end(bytes, cursor + 2);
            continue;
        }
        if let Some(end) = raw_string_end(bytes, cursor) {
            if keep_literals {
                tokens.push(source[cursor..end].to_owned());
            }
            cursor = end;
            continue;
        }
        if bytes[cursor] == b'"' {
            let end = quoted_string_end(bytes, cursor + 1);
            if keep_literals {
                tokens.push(source[cursor..end].to_owned());
            }
            cursor = end;
            continue;
        }
        if matches!(bytes[cursor], b'b' | b'c') && bytes.get(cursor + 1) == Some(&b'"') {
            let end = quoted_string_end(bytes, cursor + 2);
            if keep_literals {
                tokens.push(source[cursor..end].to_owned());
            }
            cursor = end;
            continue;
        }
        if bytes[cursor] == b'\''
            && let Some(end) = char_literal_end(source, cursor)
        {
            if keep_literals {
                tokens.push(source[cursor..end].to_owned());
            }
            cursor = end;
            continue;
        }
        if bytes[cursor] == b'b'
            && bytes.get(cursor + 1) == Some(&b'\'')
            && let Some(end) = char_literal_end(source, cursor + 1)
        {
            if keep_literals {
                tokens.push(source[cursor..end].to_owned());
            }
            cursor = end;
            continue;
        }
        if let Some((identifier, end)) = raw_identifier(source, cursor) {
            tokens.push(identifier.to_owned());
            cursor = end;
            continue;
        }

        if character == '_' || character.is_alphabetic() {
            let start = cursor;
            cursor += character.len_utf8();
            while cursor < bytes.len() {
                let next = source[cursor..]
                    .chars()
                    .next()
                    .expect("cursor 始终位于源码字符边界");
                if next == '_' || next.is_alphanumeric() {
                    cursor += next.len_utf8();
                } else {
                    break;
                }
            }
            tokens.push(source[start..cursor].to_owned());
        } else {
            tokens.push(character.to_string());
            cursor += character.len_utf8();
        }
    }

    tokens
}

fn raw_identifier(source: &str, start: usize) -> Option<(&str, usize)> {
    let bytes = source.as_bytes();
    if !bytes[start..].starts_with(b"r#") {
        return None;
    }
    let identifier_start = start + 2;
    let first = source[identifier_start..].chars().next()?;
    if first != '_' && !first.is_alphabetic() {
        return None;
    }
    let mut cursor = identifier_start + first.len_utf8();
    while cursor < bytes.len() {
        let next = source[cursor..].chars().next()?;
        if next == '_' || next.is_alphanumeric() {
            cursor += next.len_utf8();
        } else {
            break;
        }
    }
    Some((&source[identifier_start..cursor], cursor))
}

/// 统计连续 token 序列出现次数。
#[must_use]
pub fn count_sequence(tokens: &[String], expected: &[&str]) -> usize {
    if expected.is_empty() {
        return 0;
    }
    tokens
        .windows(expected.len())
        .filter(|window| {
            window
                .iter()
                .map(String::as_str)
                .eq(expected.iter().copied())
        })
        .count()
}

/// 返回唯一同名函数的函数体 token；缺失、重名或花括号不平衡时返回 `None`。
#[must_use]
pub fn function_body<'a>(tokens: &'a [String], name: &str) -> Option<&'a [String]> {
    let mut declarations = tokens
        .windows(2)
        .enumerate()
        .filter(|(_, window)| window[0] == "fn" && window[1] == name);
    let declaration = declarations.next()?.0;
    if declarations.next().is_some() {
        return None;
    }
    let opening = tokens[declaration + 2..]
        .iter()
        .position(|token| token == "{")?
        + declaration
        + 2;
    let mut depth = 0_u64;
    for (offset, token) in tokens[opening..].iter().enumerate() {
        match token.as_str() {
            "{" => depth += 1,
            "}" => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    let closing = opening + offset;
                    return Some(&tokens[opening + 1..closing]);
                }
            }
            _ => {}
        }
    }
    None
}

fn line_comment_end(bytes: &[u8], mut cursor: usize) -> usize {
    while cursor < bytes.len() && bytes[cursor] != b'\n' {
        cursor += 1;
    }
    cursor
}

fn block_comment_end(bytes: &[u8], mut cursor: usize) -> usize {
    let mut depth = 1_u64;
    while cursor < bytes.len() {
        if bytes[cursor..].starts_with(b"/*") {
            depth += 1;
            cursor += 2;
        } else if bytes[cursor..].starts_with(b"*/") {
            depth -= 1;
            cursor += 2;
            if depth == 0 {
                return cursor;
            }
        } else {
            cursor += 1;
        }
    }
    bytes.len()
}

fn quoted_string_end(bytes: &[u8], mut cursor: usize) -> usize {
    while cursor < bytes.len() {
        match bytes[cursor] {
            b'\\' => cursor = (cursor + 2).min(bytes.len()),
            b'"' => return cursor + 1,
            _ => cursor += 1,
        }
    }
    bytes.len()
}

fn raw_string_end(bytes: &[u8], start: usize) -> Option<usize> {
    let mut cursor = start;
    if matches!(bytes.get(cursor), Some(b'b' | b'c')) {
        cursor += 1;
    }
    if bytes.get(cursor) != Some(&b'r') {
        return None;
    }
    cursor += 1;
    let hashes_start = cursor;
    while bytes.get(cursor) == Some(&b'#') {
        cursor += 1;
    }
    if bytes.get(cursor) != Some(&b'"') {
        return None;
    }
    let hashes = cursor - hashes_start;
    cursor += 1;
    while cursor < bytes.len() {
        if bytes[cursor] == b'"'
            && bytes
                .get(cursor + 1..cursor + 1 + hashes)
                .is_some_and(|suffix| suffix.iter().all(|byte| *byte == b'#'))
        {
            return Some(cursor + 1 + hashes);
        }
        cursor += 1;
    }
    Some(bytes.len())
}

fn char_literal_end(source: &str, quote: usize) -> Option<usize> {
    let bytes = source.as_bytes();
    let mut cursor = quote + 1;
    if cursor >= bytes.len() || matches!(bytes[cursor], b'\n' | b'\r') {
        return None;
    }
    if bytes[cursor] == b'\\' {
        cursor += 1;
        match *bytes.get(cursor)? {
            b'x' => cursor += 3,
            b'u' => {
                cursor += 1;
                if bytes.get(cursor) != Some(&b'{') {
                    return None;
                }
                cursor += 1;
                while bytes.get(cursor) != Some(&b'}') {
                    cursor += 1;
                    if cursor >= bytes.len() {
                        return None;
                    }
                }
                cursor += 1;
            }
            _ => cursor += 1,
        }
    } else {
        let character = source[cursor..].chars().next()?;
        cursor += character.len_utf8();
    }
    (bytes.get(cursor) == Some(&b'\'')).then_some(cursor + 1)
}

#[cfg(test)]
mod tests {
    use std::ffi::OsStr;
    use std::fs;
    use std::path::Path;
    use std::sync::atomic::{AtomicU64, Ordering};

    use super::{
        count_sequence, function_body, rust_files_below, rust_tokens, rust_tokens_with_literals,
    };

    #[test]
    fn 路径扫描保留真实字面量且不解释字面量中的伪声明() {
        let tokens = rust_tokens_with_literals(
            r#"#[path = "cases/leaf.rs"] mod leaf;
            const SAMPLE: &str = "mod orphan;";
            // #[path = "orphan.rs"] mod orphan;
            "#,
        );

        assert_eq!(
            count_sequence(&tokens, &["path", "=", "\"cases/leaf.rs\""]),
            1
        );
        assert_eq!(count_sequence(&tokens, &["mod", "orphan", ";"]), 0);
    }

    #[test]
    fn token_扫描忽略空白注释字符串与字符字面量() {
        let source = r####"
            // self.runtime_for(
            /* self.runtime_for(
               /* self.runtime_for( */
               self.route_parts_for(
            */
            let _ordinary = "self.runtime_for({";
            let _byte = b"self.runtime_for(}";
            let _raw = r###"self.runtime_for({}"###;
            let _byte_raw = br##"self.runtime_for(}"##;
            let _open = '{';
            let _close = b'}';

            self　/* 中文块注释 */ . runtime_for // 中文行注释
            (
                resolution.mode,
            );
        "####;

        let tokens = rust_tokens(source);

        assert_eq!(
            count_sequence(&tokens, &["self", ".", "runtime_for", "("]),
            1
        );
        assert_eq!(
            count_sequence(&tokens, &["self", ".", "route_parts_for", "("]),
            0
        );
    }

    #[test]
    fn function_body_按配对花括号提取且不受字面量影响() {
        let source = r####"
            fn before() {}

            pub fn resolve_feature_route<T>(value: T) {
                let _ordinary = "}";
                let _raw = r###"{{}"###;
                let _open = '{';
                let _close = b'}';
                /* } { /* } */ */
                if true {
                    let closure = || { value };
                    resolve_route(closure());
                }
            }

            fn after() {
                resolve_route(ignored());
            }
        "####;
        let tokens = rust_tokens(source);
        let body = function_body(&tokens, "resolve_feature_route").expect("提取唯一函数体");

        assert_eq!(count_sequence(body, &["resolve_route", "("]), 1);
        assert_eq!(count_sequence(body, &["fn", "after"]), 0);
        assert!(function_body(&tokens, "missing").is_none());
    }

    #[test]
    fn raw_identifier_归一为普通标识符以免绕过架构门禁() {
        let tokens = rust_tokens(
            "self.r#direct_runtime; self.r#runtime_for(resolution.r#mode); self.r#中文字段;",
        );

        assert_eq!(count_sequence(&tokens, &["self", ".", "direct_runtime"]), 1);
        assert_eq!(
            count_sequence(&tokens, &["self", ".", "runtime_for", "("]),
            1
        );
        assert_eq!(count_sequence(&tokens, &["resolution", ".", "mode"]), 1);
        assert!(tokens.iter().any(|token| token == "中文字段"));
    }

    #[test]
    fn function_body_拒绝重名函数和不平衡花括号() {
        let duplicate = rust_tokens("fn target() {} fn target() {}");
        let unbalanced = rust_tokens("fn target() { if true {");

        assert!(function_body(&duplicate, "target").is_none());
        assert!(function_body(&unbalanced, "target").is_none());
    }

    #[test]
    fn rust_files_below_仅递归返回排序后的_rs_文件() {
        static NEXT_ROOT: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "ubaa-source-tokens-{}-{}",
            std::process::id(),
            NEXT_ROOT.fetch_add(1, Ordering::Relaxed)
        ));
        let nested = root.join("nested");
        fs::create_dir_all(&nested).expect("创建临时源码目录");
        fs::write(root.join("z.rs"), "fn z() {}").expect("写入根源码");
        fs::write(root.join("ignored.txt"), "ignored").expect("写入非源码");
        fs::write(nested.join("a.rs"), "fn a() {}").expect("写入嵌套源码");

        let files = rust_files_below(&root);
        let relative = files
            .iter()
            .map(|path| path.strip_prefix(&root).expect("得到相对路径"))
            .collect::<Vec<_>>();

        assert_eq!(relative.len(), 2);
        assert_eq!(relative[0], Path::new("nested/a.rs"));
        assert_eq!(relative[1], Path::new("z.rs"));
        assert_eq!(files[0].extension(), Some(OsStr::new("rs")));

        fs::remove_dir_all(root).expect("清理临时源码目录");
    }
}
