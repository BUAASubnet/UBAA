use std::fs;
use std::os::unix::fs::{PermissionsExt as _, symlink};

use super::*;

#[test]
fn 允许仓库内相对和绝对路径并创建私有目录() {
    let root = ubaa_test_support::test_temp_dir("core_live_diagnostics_paths").unwrap();
    let expected = root.join(".ubaa_local/课堂/direct.json");
    assert_eq!(
        prepare_path(&root, Path::new("./.ubaa_local/课堂/./direct.json")).unwrap(),
        expected
    );
    assert_eq!(prepare_path(&root, &expected).unwrap(), expected);
    for directory in [root.join(".ubaa_local"), root.join(".ubaa_local/课堂")] {
        assert_eq!(
            fs::metadata(directory).unwrap().permissions().mode() & 0o777,
            0o700
        );
    }
    assert!(!expected.exists());
}

#[test]
fn 拒绝越界路径符号链接公开目录和现有文件() {
    let root = ubaa_test_support::test_temp_dir("core_live_diagnostics_rejected_paths").unwrap();
    let outside = root.join("outside");
    fs::create_dir(&outside).unwrap();
    let local = root.join(".ubaa_local");

    symlink(&outside, &local).unwrap();
    assert!(prepare_path(&root, Path::new(".ubaa_local/escape.json")).is_err());
    fs::remove_file(&local).unwrap();
    prepare_path(&root, Path::new(".ubaa_local/task/direct.json")).unwrap();

    fs::create_dir(local.join("public")).unwrap();
    fs::set_permissions(local.join("public"), fs::Permissions::from_mode(0o755)).unwrap();
    fs::write(local.join("existing.json"), "保留现有文件").unwrap();
    symlink(&outside, local.join("escape")).unwrap();
    symlink(outside.join("leaf.json"), local.join("leaf.json")).unwrap();

    for rejected in [
        root.join("outside/absolute.json"),
        PathBuf::from("outside/relative.json"),
        PathBuf::from(".ubaa_local"),
        PathBuf::from(".ubaa_local_sibling/same-prefix.json"),
        PathBuf::from(".ubaa_local/../outside/traversal.json"),
        PathBuf::from(".ubaa_local/task/../inside.json"),
        PathBuf::from(".ubaa_local/public/open.json"),
        PathBuf::from(".ubaa_local/existing.json"),
        PathBuf::from(".ubaa_local/escape/nested/escape.json"),
        PathBuf::from(".ubaa_local/leaf.json"),
    ] {
        assert!(prepare_path(&root, &rejected).is_err(), "{rejected:?}");
    }
    assert_eq!(fs::read_dir(outside).unwrap().count(), 0);
    assert_eq!(
        fs::read_to_string(local.join("existing.json")).unwrap(),
        "保留现有文件"
    );
}
