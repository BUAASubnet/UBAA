//! 检查仓库现有 `mod`、`path` 和测试属性语法，不承担通用 Rust 解析或执行证明。
//!
//! 明确的 Unix/Windows 平台限定可跨平台保留；任意 feature/cfg 表达式不能充当测试存在性证据。

use std::collections::BTreeSet;
use std::path::{Component, Path, PathBuf};

use super::support::source_tokens::rust_tokens_with_literals;

pub fn has_declared_test(path: &Path, read_source: &impl Fn(&Path) -> Option<String>) -> bool {
    let path = normalized_path(path);
    let module_dir = path.parent().unwrap_or_else(|| Path::new(""));
    // 共享工具自身的单测不能替代该 Cargo 目标登记的领域行为测试。
    let support_dir = module_dir.join("support");
    let support_file = module_dir.join("support.rs");
    let read_behavior_source = |path: &Path| {
        if path.starts_with(&support_dir) || path == support_file {
            None
        } else {
            read_source(path)
        }
    };
    visit_file(
        &path,
        module_dir,
        &read_behavior_source,
        &mut BTreeSet::new(),
    )
}

fn visit_file(
    path: &Path,
    module_dir: &Path,
    read_source: &impl Fn(&Path) -> Option<String>,
    visited: &mut BTreeSet<PathBuf>,
) -> bool {
    let path = normalized_path(path);
    if !visited.insert(path.clone()) {
        return false;
    }
    let Some(source) = read_source(&path) else {
        return false;
    };
    visit_items(
        &rust_tokens_with_literals(&source),
        module_dir,
        path.parent().unwrap_or_else(|| Path::new("")),
        read_source,
        visited,
    )
}

#[derive(Default)]
struct Attributes {
    test: bool,
    disabled: bool,
    path: Option<String>,
}

impl Attributes {
    fn accept(&mut self, tokens: &[String]) {
        match tokens.first().map(String::as_str) {
            Some("test") if tokens.len() == 1 => self.test = true,
            Some("tokio")
                if tokens
                    .get(1..4)
                    .is_some_and(|path| path == [":", ":", "test"]) =>
            {
                self.test = true;
            }
            Some("cfg") if tokens == ["cfg", "(", "test", ")"] => {}
            Some("cfg")
                if tokens == ["cfg", "(", "unix", ")"]
                    || tokens == ["cfg", "(", "windows", ")"] => {}
            Some("cfg" | "cfg_attr" | "ignore") => self.disabled = true,
            Some("path") => {
                self.path = tokens
                    .get(2)
                    .filter(|_| tokens.len() == 3 && tokens[1] == "=")
                    .and_then(|literal| serde_json::from_str(literal).ok());
                self.disabled |= self.path.is_none();
            }
            _ => {}
        }
    }
}

// 只在 item 层查找声明，函数体和宏正文中的示例 token 不能充当可执行测试。
fn visit_items(
    tokens: &[String],
    module_dir: &Path,
    path_base: &Path,
    read_source: &impl Fn(&Path) -> Option<String>,
    visited: &mut BTreeSet<PathBuf>,
) -> bool {
    let mut cursor = 0;
    let mut attributes = Attributes::default();
    while cursor < tokens.len() {
        if tokens[cursor] == "#" {
            let inner = tokens.get(cursor + 1).is_some_and(|token| token == "!");
            let opening = cursor + if inner { 2 } else { 1 };
            if tokens.get(opening).is_some_and(|token| token == "[") {
                let Some(end) = group_end(tokens, opening, "[", "]") else {
                    return false;
                };
                attributes.accept(&tokens[opening + 1..end - 1]);
                if inner && attributes.disabled {
                    return false;
                }
                cursor = end;
                continue;
            }
        }
        if tokens[cursor] == "mod"
            && let (Some(name), Some(body)) = (tokens.get(cursor + 1), tokens.get(cursor + 2))
        {
            if body == ";" {
                if !attributes.disabled {
                    let candidates = attributes.path.as_ref().map_or_else(
                        || {
                            vec![
                                module_dir.join(format!("{name}.rs")),
                                module_dir.join(name).join("mod.rs"),
                            ]
                        },
                        |path| vec![path_base.join(path)],
                    );
                    for path in candidates {
                        let child_dir = if path.file_name().is_some_and(|name| name == "mod.rs") {
                            path.parent().expect("mod.rs 必须有父目录").to_owned()
                        } else {
                            path.with_extension("")
                        };
                        if visit_file(&path, &child_dir, read_source, visited) {
                            return true;
                        }
                    }
                }
                cursor += 3;
                attributes = Attributes::default();
                continue;
            }
            if body == "{" {
                let Some(end) = group_end(tokens, cursor + 2, "{", "}") else {
                    return false;
                };
                let child_dir = module_dir.join(name);
                if !attributes.disabled
                    && visit_items(
                        &tokens[cursor + 3..end - 1],
                        &child_dir,
                        &child_dir,
                        read_source,
                        visited,
                    )
                {
                    return true;
                }
                cursor = end;
                attributes = Attributes::default();
                continue;
            }
        }
        if tokens[cursor] == "fn" && attributes.test && !attributes.disabled {
            return true;
        }
        if tokens[cursor] == "{" {
            let Some(end) = group_end(tokens, cursor, "{", "}") else {
                return false;
            };
            cursor = end;
            attributes = Attributes::default();
        } else {
            if tokens[cursor] == ";" {
                attributes = Attributes::default();
            }
            cursor += 1;
        }
    }
    false
}

fn group_end(tokens: &[String], opening: usize, open: &str, close: &str) -> Option<usize> {
    let mut depth = 0_usize;
    for (index, token) in tokens.iter().enumerate().skip(opening) {
        if token == open {
            depth += 1;
        } else if token == close {
            depth = depth.checked_sub(1)?;
            if depth == 0 {
                return Some(index + 1);
            }
        }
    }
    None
}

fn normalized_path(path: &Path) -> PathBuf {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                if normalized.file_name().is_some_and(|name| name != "..") {
                    normalized.pop();
                } else if !normalized.has_root() {
                    normalized.push("..");
                }
            }
            _ => normalized.push(component.as_os_str()),
        }
    }
    normalized
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::has_declared_test;

    #[test]
    fn 薄入口可沿实际_path_声明发现测试叶() {
        assert!(has_test(&[
            ("root.rs", "#[path = \"cases/leaf.rs\"] mod leaf;"),
            ("cases/leaf.rs", "#[test] fn contract() {}"),
        ]));
    }

    #[test]
    fn 普通模块声明可逐层找到测试叶() {
        assert!(has_test(&[
            ("root.rs", "mod cases;"),
            ("cases.rs", "mod leaf;"),
            ("cases/leaf.rs", "#[tokio::test] async fn contract() {}"),
        ]));
    }

    #[test]
    fn 空入口及未引用测试文件不能通过() {
        for root in ["", "mod empty;"] {
            assert!(!has_test(&[
                ("root.rs", root),
                ("empty.rs", "fn helper() {}"),
                ("orphan.rs", "#[test] fn ignored() {}"),
            ]));
        }
    }

    #[test]
    fn 注释和字符串中的模块及测试声明不能通过() {
        assert!(!has_test(&[
            (
                "root.rs",
                "// mod orphan;\nconst TEXT: &str = \"#[test] fn fake() {}\";",
            ),
            ("orphan.rs", "#[test] fn ignored() {}"),
        ]));
    }

    #[test]
    fn 源码_cfg_不能静默删除唯一测试() {
        for root in [
            "#![cfg(feature = \"missing\")] #[test] fn hidden() {}",
            "#[cfg(any())] #[test] fn hidden() {}",
            "#[cfg(feature = \"missing\")] mod leaf;",
            "#[cfg_attr(test, ignore)] #[test] fn hidden() {}",
            "#[ignore] #[test] fn hidden() {}",
        ] {
            assert!(!has_test(&[
                ("root.rs", root),
                ("leaf.rs", "#[test] fn hidden() {}"),
            ]));
        }
    }

    #[test]
    fn 两类明确平台_cfg_都保留跨平台测试声明() {
        for source in [
            "#![cfg(unix)] #[test] fn platform() {}",
            "#![cfg(windows)] #[test] fn platform() {}",
        ] {
            assert!(has_test(&[("root.rs", source)]));
        }
    }

    #[test]
    fn 共享_support_自测不能代替目标行为测试() {
        for declaration in ["mod support;", "#[path = \"support/mod.rs\"] mod renamed;"] {
            assert!(!has_test(&[
                ("root.rs", declaration),
                ("support/mod.rs", "#[test] fn helper_only() {}"),
            ]));
        }
    }

    #[test]
    fn path_父目录声明不能误读同目录未引用文件() {
        assert!(!has_test(&[
            ("root.rs", "#[path = \"../leaf.rs\"] mod leaf;"),
            ("../leaf.rs", "fn helper() {}"),
            ("leaf.rs", "#[test] fn unreferenced() {}"),
        ]));
    }

    fn has_test(sources: &[(&str, &str)]) -> bool {
        has_declared_test(Path::new("root.rs"), &|path| {
            sources
                .iter()
                .find(|(name, _)| path == Path::new(name))
                .map(|(_, source)| (*source).to_owned())
        })
    }
}
