use std::process::Command;
fn collect_source_files(root: &std::path::Path, files: &mut Vec<std::path::PathBuf>) {
    for entry in std::fs::read_dir(root).expect("could not enumerate CLI sources") {
        let entry = entry.expect("could not inspect CLI source entry");
        let path = entry.path();
        if path.is_dir() {
            collect_source_files(&path, files);
        } else if path.extension().is_some_and(|extension| extension == "rs") {
            files.push(path);
        }
    }
}

fn core_live_source_bundle() -> String {
    let manifest_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let source_root = manifest_root.join("src");
    assert!(
        source_root.is_dir(),
        "Core-live must use the explicit src module tree"
    );
    assert!(
        !manifest_root.join("src/bin/core-live.rs").exists(),
        "legacy auto-discovered Core-live source must be removed"
    );

    let mut files = Vec::new();
    collect_source_files(&source_root, &mut files);
    files.sort();
    let relative_files: Vec<_> = files
        .iter()
        .map(|path| {
            path.strip_prefix(&source_root)
                .expect("Core-live source stays below its module root")
                .to_string_lossy()
                .replace('\\', "/")
        })
        .collect();
    assert_eq!(
        relative_files,
        ["args.rs", "evidence.rs", "main.rs", "steps.rs"]
    );

    let manifest = include_str!("../Cargo.toml");
    assert!(manifest.contains("autobins = false"));
    assert!(manifest.contains("name = \"core-live\"\npath = \"src/main.rs\""));

    let sources: std::collections::BTreeMap<_, _> = files
        .iter()
        .map(|path| {
            let name = path
                .file_name()
                .expect("Core-live source has a file name")
                .to_string_lossy()
                .into_owned();
            let source = std::fs::read_to_string(path)
                .unwrap_or_else(|_| panic!("could not read Core-live source {}", path.display()));
            (name, source)
        })
        .collect();
    let main = &sources["main.rs"];
    assert!(main.contains("steps::process().await"));
    for forbidden in ["Args::", "Evidence", "ubaa_core::"] {
        assert!(
            !main.contains(forbidden),
            "main bypasses steps via {forbidden}"
        );
    }
    let args = &sources["args.rs"];
    assert!(!args.contains("crate::"));
    assert!(!args.contains("ubaa_core::"));
    let evidence = &sources["evidence.rs"];
    assert!(evidence.contains("ubaa_core::facade::ErrorCode"));
    for forbidden in [
        "crate::args",
        "crate::steps",
        "ubaa_core::domain",
        "ubaa_core::error",
    ] {
        assert!(!evidence.contains(forbidden));
    }
    let steps = &sources["steps.rs"];
    for dependency in [
        "crate::args",
        "crate::evidence",
        "ubaa_core::facade::RouteClient",
    ] {
        assert!(
            steps.contains(dependency),
            "steps misses dependency {dependency}"
        );
    }

    sources.into_values().collect::<Vec<_>>().join("\n")
}

fn assert_ordered_fragments(source: &str, fragments: &[&str], context: &str) {
    let mut cursor = 0;
    for fragment in fragments {
        let offset = source[cursor..]
            .find(fragment)
            .unwrap_or_else(|| panic!("{context} 顺序缺少 {fragment}"));
        cursor += offset + fragment.len();
    }
}

fn contains_directory_named(root: &std::path::Path, name: &str) -> bool {
    std::fs::read_dir(root)
        .expect("could not enumerate source tree")
        .filter_map(Result::ok)
        .any(|entry| {
            let path = entry.path();
            path.is_dir()
                && (path.file_name().is_some_and(|file_name| file_name == name)
                    || contains_directory_named(&path, name))
        })
}

fn imports_core_output(source: &str) -> bool {
    let compact: String = source
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect();
    if compact.contains("ubaa_core::output")
        || compact.split(';').any(|statement| {
            statement.starts_with("useubaa_core::{") && statement.contains("output")
        })
    {
        return true;
    }

    let aliases = compact.split(';').filter_map(|statement| {
        statement
            .strip_prefix("useubaa_coreas")
            .or_else(|| statement.strip_prefix("useubaa_core::{selfas"))
            .and_then(|alias| alias.split([',', '}']).next())
            .filter(|alias| !alias.is_empty())
    });
    aliases.into_iter().any(|alias| {
        compact.contains(&format!("use{alias}::output"))
            || compact.contains(&format!("{alias}::output::"))
    })
}

#[test]
fn repository_gate_include_uses_tracked_justfile_case() {
    let source = include_str!("source_boundaries.rs");
    let include = source
        .lines()
        .find(|line| line.trim_start().starts_with("let justfile = include_str!"))
        .expect("repository gate must embed the tracked justfile");

    assert_eq!(
        include.trim(),
        r#"let justfile = include_str!("../../../justfile");"#
    );
}

#[test]
fn repository_cargo_gates_lock_dependency_resolution() {
    let justfile = include_str!("../../../justfile");
    let repository_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let tracked = Command::new("git")
        .current_dir(&repository_root)
        .args([
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
            "--",
            "justfile",
            "*.md",
            ".github/workflows/*",
            "scripts/*.sh",
        ])
        .output()
        .expect("git must enumerate tracked command sources");
    assert!(tracked.status.success());
    let tracked = String::from_utf8(tracked.stdout).expect("tracked paths must be UTF-8");

    assert!(
        justfile.contains("cargo metadata --locked --no-deps --format-version 1"),
        "justfile must validate Cargo.lock before running deterministic gates"
    );

    for source_name in tracked.split('\0').filter(|path| !path.is_empty()) {
        if !repository_root.join(source_name).is_file() {
            continue;
        }
        let source = std::fs::read_to_string(repository_root.join(source_name))
            .unwrap_or_else(|_| panic!("could not read tracked command source {source_name}"));
        for line in source.lines().map(str::trim) {
            let Some(cargo_index) = line.find("cargo ") else {
                continue;
            };
            let cargo_command = &line[cargo_index..];
            if cargo_command.starts_with("cargo fmt ") {
                continue;
            }
            assert!(
                cargo_command.contains("--locked"),
                "{source_name} has an unlocked Cargo command: {cargo_command}"
            );
        }
    }
}

#[test]
fn cli_production_sources_use_only_facade_for_core_internals() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    let forbidden = [
        "ubaa_core::connection",
        "ubaa_core::domain",
        "ubaa_core::error",
        "ubaa_core::session",
        "ubaa_core::features",
        "ubaa_core::runtime",
        "ubaa_core::upstream",
        "FileSessionStore",
        "SessionStore",
        "ReqwestTransport",
    ];
    let mut files = Vec::new();
    collect_source_files(&root, &mut files);
    collect_source_files(&root.join("../../../crates/ubaa_command/src"), &mut files);
    for path in files {
        let source = std::fs::read_to_string(&path)
            .unwrap_or_else(|_| panic!("could not read CLI source {}", path.display()));
        for item in forbidden {
            assert!(
                !source.contains(item),
                "CLI production source {} reaches through Core boundary: {item}",
                path.display()
            );
        }
    }
}

#[test]
fn core_does_not_own_cli_output_or_exit_policy() {
    let repository_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let core_root = repository_root.join("crates/ubaa_core");
    let core_source_root = core_root.join("src");
    let mut core_sources = Vec::new();
    collect_source_files(&core_source_root, &mut core_sources);
    let mut cli_sources = Vec::new();
    collect_source_files(
        &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src"),
        &mut cli_sources,
    );

    collect_source_files(
        &repository_root.join("crates/ubaa_command/src"),
        &mut cli_sources,
    );
    let mut violations = Vec::new();
    for source in [
        "use ubaa_core::output::CliFeature;",
        "use ubaa_core::{output::{CliFeature}};",
        "use ubaa_core::output as cli_output;",
        "use ubaa_core as core; use core::output::CliFeature;",
        "use ubaa_core::{self as core}; use core::output::CliFeature;",
        "use ubaa_core::{self as core, facade::UbaaClient}; use core::output::CliFeature;",
    ] {
        assert!(
            imports_core_output(source),
            "missed forbidden import: {source}"
        );
    }
    for source in [
        "use ubaa_core::facade::UbaaClient;",
        "let output = command_output_value(value);",
    ] {
        assert!(
            !imports_core_output(source),
            "false positive import: {source}"
        );
    }
    if contains_directory_named(&core_source_root, "output") {
        violations.push("Core still owns an output source directory".to_owned());
    }
    for path in core_sources {
        if path
            .file_name()
            .is_some_and(|file_name| file_name == "output.rs")
        {
            violations.push(format!("Core still owns {}", path.display()));
        }
        let source = std::fs::read_to_string(&path).expect("could not read Core production source");
        let compact: String = source
            .chars()
            .filter(|character| !character.is_whitespace())
            .collect();
        for symbol in [
            "CLI_JSON_SCHEMA_VERSION",
            "CliFeature",
            "ResolvedRoutedJsonMeta",
            "UnresolvedRoutedJsonMeta",
            "RoutedJsonMeta",
            "CliJsonError",
            "RoutedJsonEnvelope",
            "AggregateJsonMeta",
            "AggregateJsonEnvelope",
            "AggregateLogoutRouteState",
            "AggregateLogoutRoute",
            "AggregateLogoutData",
            "validate_auth_outcome",
            "output_invariant_error",
            "error_code_name",
            "error_kind_name",
            "is_error_code",
            "is_error_kind",
            "ExitCode",
            "exit_code(",
        ] {
            if compact.contains(symbol) {
                violations.push(format!(
                    "Core production source {} still owns CLI symbol {symbol}",
                    path.display()
                ));
            }
        }
    }
    for path in cli_sources {
        let source = std::fs::read_to_string(&path).expect("could not read CLI production source");
        if imports_core_output(&source) {
            violations.push(format!(
                "CLI production source {} still imports Core output",
                path.display()
            ));
        }
    }

    assert!(
        violations.is_empty(),
        "CLI output ownership violations ({}):\n{}",
        violations.len(),
        violations.join("\n")
    );
}

#[test]
fn core_live_is_single_route_read_only_and_verify_live_is_thin() {
    let core_live = core_live_source_bundle();
    assert_eq!(core_live.matches("RouteClient::new").count(), 1);
    for forbidden in [
        "cgyy_cancel_order",
        "cgyy_submit_reservation",
        "bykc_select_course",
        "bykc_deselect_course",
        "bykc_sign_course",
        "signin_perform",
        "libbook_reserve",
        "libbook_cancel_booking",
        "evaluation_submit",
        "evaluation_submit_courses",
        "commit_write",
    ] {
        assert!(
            !core_live.contains(forbidden),
            "Core-live contains write call {forbidden}"
        );
    }
    let compact_core_live: String = core_live
        .chars()
        .filter(|character| !character.is_whitespace())
        .collect();
    assert!(
        !compact_core_live
            .replace(".prepare_login(", "")
            .contains(".prepare_"),
        "Core-live contains a generic write preparation call"
    );
    let verifier = include_str!("../../../scripts/live/verify.sh");
    for forbidden in ["run_json", "target/debug/ubaa", "jq ", "CLI_OUTPUT"] {
        assert!(
            !verifier.contains(forbidden),
            "verify-live retained business logic {forbidden}"
        );
    }
    assert!(verifier.matches("core_live").count() >= 3);
}

#[test]
fn core_live_matrix_contains_shared_diagnostic_rows_and_no_guessed_week() {
    let core_live = core_live_source_bundle();
    for label in [
        "\"spoc\",\n                \"diagnostics\"",
        "\"judge\",\n                \"diagnostics\"",
    ] {
        assert!(
            core_live.contains(label),
            "Core-live 缺少诊断矩阵行: {label}"
        );
    }
    assert!(core_live.contains("no_valid_week_id"));
    assert!(!core_live.contains("map_or(1"));

    let feature_list = core_live
        .split_once("pub(crate) const FEATURES")
        .expect("Core-live keeps the explicit feature matrix")
        .1;
    assert_ordered_fragments(
        feature_list,
        &[
            "\"all\"",
            "\"auth\"",
            "\"user\"",
            "\"schedule\"",
            "\"exam\"",
            "\"grades\"",
            "\"classroom\"",
            "\"spoc\"",
            "\"judge\"",
            "\"signin\"",
            "\"ygdk\"",
            "\"libbook\"",
            "\"bykc\"",
            "\"cgyy\"",
            "\"evaluation\"",
        ],
        "Core-live feature",
    );

    let runner = &core_live[core_live
        .find("async fn run(args")
        .expect("Core-live keeps one sequential runner")..];
    assert_ordered_fragments(
        runner,
        &[
            "prepare_login",
            ".login(",
            "run_auth_status",
            "run_user",
            "run_schedule",
            "run_classroom",
            "run_spoc",
            "run_judge",
            "signin_today",
            "run_ygdk",
            "run_libbook",
            "run_bykc",
            "run_cgyy",
            "run_evaluation",
        ],
        "Core-live operation",
    );

    for error_name in [
        "invalid_input",
        "authentication_required",
        "invalid_credentials",
        "password_risk_confirmation_failed",
        "permission_denied",
        "network_error",
        "timeout",
        "upstream_unavailable",
        "outcome_unknown",
        "upstream_changed",
        "parse_error",
        "internal_error",
    ] {
        assert!(core_live.contains(error_name));
    }
    assert_eq!(core_live.matches("self.failed = true").count(), 2);
    assert_eq!(core_live.matches("self.failed = false").count(), 0);
    assert_ordered_fragments(
        &core_live,
        &[
            "route={route}",
            "feature={feature}",
            "stage={feature}",
            "operation={operation}",
            "status={status}",
            "elapsed_ms={elapsed_ms}",
        ],
        "Core-live evidence field",
    );
    assert!(core_live.contains("let username = lines.next()"));
    assert!(core_live.contains("let password = lines.next()"));
    assert!(core_live.contains("std::process::exit(2)"));
    assert!(core_live.contains("Ok(evidence) if evidence.failed() => 5"));
    assert!(core_live.contains("Ok(_) => 0"));
}

#[test]
fn windows_cargokit_manifest_avoids_plugin_junction_parent_traversal() {
    let windows_cmake = include_str!("../../../packages/ubaa_bindings/windows/CMakeLists.txt");
    let cargokit_cmake =
        include_str!("../../../packages/ubaa_bindings/cargokit/cmake/cargokit.cmake");

    assert!(windows_cmake.contains("${CMAKE_SOURCE_DIR}/../../../crates/ubaa_flutter_bridge"));
    assert!(windows_cmake.contains(
        "apply_cargokit(${PROJECT_NAME} \"${UBAA_RUST_CRATE_DIR}\" ubaa_flutter_bridge \"\")"
    ));
    assert!(
        !windows_cmake
            .contains("apply_cargokit(${PROJECT_NAME} ../../../crates/ubaa_flutter_bridge")
    );
    assert!(cargokit_cmake.contains("if(IS_ABSOLUTE \"${manifest_dir}\")"));
    assert!(cargokit_cmake.contains("CARGOKIT_MANIFEST_DIR=${CARGOKIT_MANIFEST_DIR}"));
}
