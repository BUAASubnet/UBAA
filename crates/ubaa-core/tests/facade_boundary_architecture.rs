//! Core facade、测试注入面与生产宿主依赖方向的架构门禁。

mod support;

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use support::source_tokens::{count_sequence, rust_files_below, rust_tokens};

const LEGACY_PUBLIC_MODULES: [&str; 6] = [
    "auth",
    "config",
    "connection",
    "features",
    "ports",
    "session",
];

const TEST_CONSTRUCTORS: [(&str, &str); 3] = [
    ("src/facade/diagnostic.rs", "with_transport"),
    ("src/facade/client.rs", "with_transports"),
    ("src/facade/client.rs", "with_routing"),
];

#[test]
fn cli_与_bridge_生产源码只能通过_facade_引用_core() {
    let repository = repository_root();
    let hosts = [
        ("CLI", repository.join("apps/ubaa-cli/src")),
        (
            "Flutter bridge",
            repository.join("crates/ubaa-flutter-bridge/src"),
        ),
        (
            "Test Support",
            repository.join("crates/ubaa-test-support/src"),
        ),
    ];
    let mut violations = Vec::new();

    for (host, source_root) in hosts {
        for path in rust_files_below(&source_root) {
            if path.file_name().is_some_and(|name| name == "tests.rs") {
                continue;
            }
            let source = read(&path);
            let tokens = production_tokens(&rust_tokens(&source));
            for reference in non_facade_core_references(&tokens) {
                violations.push(format!(
                    "{host} 的 {} 绕过 facade：{reference}",
                    relative_to_repository(&path).display()
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "生产宿主只能引用 ubaa_core::facade（共 {} 项）：\n{}",
        violations.len(),
        violations.join("\n")
    );
}

#[test]
fn core_旧实现模块不再形成公开旁路() {
    let lib = manifest_dir().join("src/lib.rs");
    let tokens = rust_tokens(&read(&lib));
    let public = LEGACY_PUBLIC_MODULES
        .into_iter()
        .filter(|module| count_sequence(&tokens, &["pub", "mod", *module]) > 0)
        .collect::<Vec<_>>();

    assert!(
        public.is_empty(),
        "以下旧实现模块仍由 crate 根公开，宿主可绕过 facade：{}",
        public.join(", ")
    );
}

#[test]
fn test_contract_是关闭默认值且仅由测试支持显式启用() {
    let repository = repository_root();
    let core = parse_manifest(&manifest_dir().join("Cargo.toml"));
    let test_support = parse_manifest(&repository.join("crates/ubaa-test-support/Cargo.toml"));
    let cli = parse_manifest(&repository.join("apps/ubaa-cli/Cargo.toml"));
    let bridge = parse_manifest(&repository.join("crates/ubaa-flutter-bridge/Cargo.toml"));
    let mut violations = Vec::new();

    if let Some(features) = core.get("features").and_then(toml::Value::as_table) {
        for feature in ["default", "test-contract"] {
            match string_array(features.get(feature)) {
                Some(values) if values.is_empty() => {}
                Some(values) => violations.push(format!(
                    "ubaa-core feature `{feature}` 必须为空数组，当前为 {values:?}"
                )),
                None => violations.push(format!("ubaa-core 缺少空 feature `{feature}`")),
            }
        }
    } else {
        violations.push("ubaa-core 必须声明 [features]".to_owned());
    }

    let support_dependencies = dependency_declarations(&test_support, "ubaa-core");
    if support_dependencies.len() != 1 {
        violations.push(format!(
            "ubaa-test-support 必须只声明一个 ubaa-core 依赖，当前为 {} 个",
            support_dependencies.len()
        ));
    }
    for dependency in &support_dependencies {
        if !matches!(
            dependency.features.as_slice(),
            [feature] if feature == "test-contract"
        ) {
            violations.push(format!(
                "ubaa-test-support 的 {} 必须且只能启用 test-contract，当前为 {:?}",
                dependency.location, dependency.features
            ));
        }
    }

    for (host, manifest) in [("ubaa-cli", &cli), ("ubaa-flutter-bridge", &bridge)] {
        let dependencies = dependency_declarations(manifest, "ubaa-core");
        if dependencies.is_empty() {
            violations.push(format!("{host} manifest 必须显式声明 ubaa-core 生产依赖"));
        }
        for dependency in dependencies {
            if dependency
                .features
                .iter()
                .any(|feature| feature == "test-contract")
            {
                violations.push(format!(
                    "{host} 的 {} 不得启用 test-contract",
                    dependency.location
                ));
            }
        }
    }

    assert!(
        violations.is_empty(),
        "test-contract Cargo 边界不完整（共 {} 项）：\n{}",
        violations.len(),
        violations.join("\n")
    );
}

#[test]
fn 测试注入模块与三个构造器仅在_test_contract_下编译() {
    let facade_mod = rust_tokens(&read(&manifest_dir().join("src/facade/mod.rs")));
    assert_guarded_declaration(&facade_mod, "mod", "testing", "facade::testing");

    for (relative, constructor) in TEST_CONSTRUCTORS {
        let tokens = rust_tokens(&read(&manifest_dir().join(relative)));
        assert_guarded_declaration(&tokens, "fn", constructor, constructor);
    }
}

#[test]
fn feature_on_off_compile_fixture_只改变依赖feature且不会被_cfg_静默跳过() {
    let fixtures = manifest_dir().join("tests/compile");
    let off = fixtures.join("facade_testing_feature_off");
    let on = fixtures.join("facade_testing_feature_on");
    let off_manifest = parse_manifest(&off.join("Cargo.toml"));
    let on_manifest = parse_manifest(&on.join("Cargo.toml"));
    let off_source = read(&off.join("src/main.rs"));
    let on_source = read(&on.join("src/main.rs"));

    assert_eq!(
        off_source, on_source,
        "feature-on/off 必须编译同一份调用源码，差异只能来自依赖 feature"
    );
    let tokens = rust_tokens(&off_source);
    assert_eq!(
        count_sequence(&tokens, &["cfg", "("]),
        0,
        "compile fixture 不得用 cfg 静默删除待验证调用"
    );
    assert_eq!(
        count_sequence(
            &tokens,
            &["ubaa_core", ":", ":", "facade", ":", ":", "testing"]
        ),
        1,
        "compile fixture 必须显式导入 facade::testing"
    );
    for (_, constructor) in TEST_CONSTRUCTORS {
        assert_eq!(
            count_sequence(&tokens, &[constructor, "("]),
            1,
            "compile fixture 必须调用 {constructor} 一次"
        );
    }

    assert_eq!(
        dependency_features(&off_manifest, "ubaa-core"),
        Some(Vec::new()),
        "feature-off fixture 不得启用任何 ubaa-core feature"
    );
    assert_eq!(
        dependency_features(&on_manifest, "ubaa-core"),
        Some(vec!["test-contract".to_owned()]),
        "feature-on fixture 必须只启用 test-contract"
    );
}

#[derive(Debug)]
struct DependencyDeclaration {
    location: String,
    features: Vec<String>,
}

fn dependency_declarations(
    manifest: &toml::Value,
    package_name: &str,
) -> Vec<DependencyDeclaration> {
    fn visit(
        value: &toml::Value,
        location: &str,
        package_name: &str,
        declarations: &mut Vec<DependencyDeclaration>,
    ) {
        let Some(table) = value.as_table() else {
            return;
        };
        for (key, child) in table {
            let child_location = if location.is_empty() {
                key.clone()
            } else {
                format!("{location}.{key}")
            };
            if matches!(
                key.as_str(),
                "dependencies" | "dev-dependencies" | "build-dependencies"
            ) && let Some(dependencies) = child.as_table()
            {
                for (dependency_name, declaration) in dependencies {
                    let declared_package = declaration
                        .as_table()
                        .and_then(|details| details.get("package"))
                        .and_then(toml::Value::as_str)
                        .unwrap_or(dependency_name);
                    if declared_package == package_name {
                        declarations.push(DependencyDeclaration {
                            location: format!("{child_location}.{dependency_name}"),
                            features: dependency_feature_list(declaration),
                        });
                    }
                }
            }
            visit(child, &child_location, package_name, declarations);
        }
    }

    let mut declarations = Vec::new();
    visit(manifest, "", package_name, &mut declarations);
    declarations
}

fn dependency_features(manifest: &toml::Value, package_name: &str) -> Option<Vec<String>> {
    let declarations = dependency_declarations(manifest, package_name);
    if declarations.len() == 1 {
        Some(declarations[0].features.clone())
    } else {
        None
    }
}

fn dependency_feature_list(declaration: &toml::Value) -> Vec<String> {
    declaration
        .as_table()
        .and_then(|details| string_array(details.get("features")))
        .unwrap_or_default()
}

fn string_array(value: Option<&toml::Value>) -> Option<Vec<String>> {
    value?
        .as_array()?
        .iter()
        .map(|entry| entry.as_str().map(ToOwned::to_owned))
        .collect()
}

fn assert_guarded_declaration(tokens: &[String], kind: &str, name: &str, label: &str) {
    let declarations = tokens
        .windows(2)
        .enumerate()
        .filter(|(_, window)| window[0] == kind && window[1] == name)
        .map(|(index, _)| index)
        .collect::<Vec<_>>();
    assert_eq!(declarations.len(), 1, "必须且只能声明一个测试入口 {label}");
    let declaration = declarations[0];
    let attributes = &tokens[declaration.saturating_sub(32)..declaration];
    assert!(
        count_sequence(
            attributes,
            &["#", "[", "cfg", "(", "feature", "=", ")", "]"]
        ) > 0,
        "{label} 必须由 Cargo feature 属性保护"
    );
    assert!(
        count_sequence(attributes, &["#", "[", "doc", "(", "hidden", ")", "]"]) > 0,
        "{label} 必须标记为 doc(hidden)"
    );
}

fn non_facade_core_references(tokens: &[String]) -> Vec<String> {
    let references = tokens
        .iter()
        .enumerate()
        .filter(|(_, token)| token.as_str() == "ubaa_core")
        .filter(|(index, _)| !is_facade_reference(tokens, *index))
        .map(|(index, _)| tokens[index..tokens.len().min(index + 10)].join(" "))
        .collect::<BTreeSet<_>>();
    references.into_iter().collect()
}

fn is_facade_reference(tokens: &[String], index: usize) -> bool {
    let Some(suffix) = tokens.get(index + 1..) else {
        return false;
    };
    if suffix.starts_with(&[":".to_owned(), ":".to_owned(), "facade".to_owned()]) {
        return true;
    }
    if !suffix.starts_with(&[":".to_owned(), ":".to_owned(), "{".to_owned()]) {
        return false;
    }

    let mut depth = 1_u64;
    let mut expects_item = true;
    let mut found_item = false;
    for token in &suffix[3..] {
        match token.as_str() {
            "{" => depth += 1,
            "}" => {
                depth -= 1;
                if depth == 0 {
                    return found_item;
                }
            }
            "," if depth == 1 => expects_item = true,
            "facade" if depth == 1 && expects_item => {
                expects_item = false;
                found_item = true;
            }
            _ if depth == 1 && expects_item => return false,
            _ => {}
        }
    }
    false
}

fn production_tokens(tokens: &[String]) -> Vec<String> {
    const CFG_TEST: [&str; 7] = ["#", "[", "cfg", "(", "test", ")", "]"];
    let mut production = Vec::with_capacity(tokens.len());
    let mut cursor = 0;
    while cursor < tokens.len() {
        let is_test_item = tokens[cursor..]
            .iter()
            .take(CFG_TEST.len())
            .map(String::as_str)
            .eq(CFG_TEST);
        if is_test_item {
            cursor = cfg_item_end(tokens, cursor + CFG_TEST.len());
        } else {
            production.push(tokens[cursor].clone());
            cursor += 1;
        }
    }
    production
}

fn cfg_item_end(tokens: &[String], mut cursor: usize) -> usize {
    while tokens.get(cursor).is_some_and(|token| token == "#") {
        cursor += 1;
        let mut brackets = 0_u64;
        while cursor < tokens.len() {
            match tokens[cursor].as_str() {
                "[" => brackets += 1,
                "]" => {
                    brackets = brackets.saturating_sub(1);
                    cursor += 1;
                    if brackets == 0 {
                        break;
                    }
                    continue;
                }
                _ => {}
            }
            cursor += 1;
        }
    }

    while cursor < tokens.len() {
        match tokens[cursor].as_str() {
            ";" => return cursor + 1,
            "{" => return matching_brace_end(tokens, cursor),
            _ => cursor += 1,
        }
    }
    tokens.len()
}

fn matching_brace_end(tokens: &[String], mut cursor: usize) -> usize {
    let mut depth = 0_u64;
    while cursor < tokens.len() {
        match tokens[cursor].as_str() {
            "{" => depth += 1,
            "}" => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    return cursor + 1;
                }
            }
            _ => {}
        }
        cursor += 1;
    }
    tokens.len()
}

fn parse_manifest(path: &Path) -> toml::Value {
    toml::from_str(&read(path)).unwrap_or_else(|error| panic!("解析 {}: {error}", path.display()))
}

fn read(path: &Path) -> String {
    std::fs::read_to_string(path).unwrap_or_else(|error| panic!("读取 {}: {error}", path.display()))
}

fn manifest_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn repository_root() -> PathBuf {
    manifest_dir().join("../..")
}

fn relative_to_repository(path: &Path) -> &Path {
    path.strip_prefix(repository_root()).unwrap_or(path)
}
