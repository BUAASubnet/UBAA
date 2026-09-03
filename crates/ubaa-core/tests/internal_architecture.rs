//! Core 内部运行时与路线状态的物理边界门禁。

mod support;

use std::path::{Path, PathBuf};

use support::source_tokens::{count_sequence, rust_files_below, rust_tokens};

#[test]
fn internal_层不得反向依赖业务_features() {
    let internal = manifest_dir().join("src/internal");
    let files = rust_files_below(&internal);

    assert!(!files.is_empty(), "必须发现 internal 层 Rust 源文件");
    for path in files {
        let source = std::fs::read_to_string(&path)
            .unwrap_or_else(|error| panic!("读取 {}: {error}", path.display()));
        let tokens = rust_tokens(&source);
        assert_eq!(
            count_sequence(&tokens, &["crate", ":", ":", "features"]),
            0,
            "{} 不得反向依赖 crate::features",
            relative_to_manifest(&path).display()
        );
    }
}

#[test]
fn 内部运行时与路线状态保持迁移后的物理结构() {
    let manifest = manifest_dir();
    let removed = [
        "src/runtime.rs",
        "src/features/state.rs",
        "src/features/state_cache.rs",
    ];
    let required = [
        "src/internal/runtime.rs",
        "src/internal/route_state/mod.rs",
        "src/internal/route_state/cache.rs",
        "src/internal/route_state/credentials.rs",
        "src/internal/route_state/classroom.rs",
    ];

    for relative in removed {
        assert!(
            !manifest.join(relative).exists(),
            "旧实现路径必须移除：{relative}"
        );
    }
    for relative in required {
        assert!(
            manifest.join(relative).is_file(),
            "迁移后的实现文件必须存在：{relative}"
        );
    }
}

fn manifest_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn relative_to_manifest(path: &Path) -> &Path {
    path.strip_prefix(manifest_dir()).unwrap_or(path)
}
