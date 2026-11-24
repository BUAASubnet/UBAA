use std::{env, fs, path::PathBuf};
use ubaa_test_support::test_temp_dir;

#[test]
fn test_directory_uses_configured_root_and_drop_removes_only_its_run() {
    let configured_root = env::var_os("UBAA_TEST_TMP")
        .filter(|path| !path.is_empty())
        .map_or_else(
            || PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/test_tmp"),
            PathBuf::from,
        );
    fs::create_dir_all(&configured_root).unwrap();
    let configured_root = configured_root.canonicalize().unwrap();
    let directory = test_temp_dir("ubaa_test_support").unwrap();
    let path = directory.path().to_path_buf();
    let sibling = test_temp_dir("ubaa_test_support").unwrap();
    let sibling_path = sibling.path().to_path_buf();
    assert!(path.starts_with(configured_root));
    assert!(path.is_dir());
    assert_ne!(path, sibling_path);
    fs::write(path.join("fixture"), "synthetic").unwrap();
    drop(directory);
    assert!(!path.exists());
    assert!(sibling_path.is_dir());
    drop(sibling);
    assert!(!sibling_path.exists());
}
