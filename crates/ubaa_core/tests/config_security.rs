#![cfg(unix)]

use std::fs;
use std::os::unix::fs::{PermissionsExt, symlink};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Barrier};

use ubaa_core::facade::testing::RouteConfig;

struct TestDir(PathBuf);

impl TestDir {
    fn new(label: &str) -> Self {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let suffix = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "ubaa-config-security-{label}-{}-{suffix}",
            std::process::id()
        ));
        fs::create_dir(&path).expect("create isolated test directory");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TestDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn load_rejects_symlinked_config_without_reading_target() {
    let root = TestDir::new("load-symlink");
    let config_dir = root.path().join("config");
    fs::create_dir(&config_dir).unwrap();
    let target = root.path().join("target.toml");
    let original = "schema_version = 1\n\n[route]\ndefault = \"direct\"\n";
    fs::write(&target, original).unwrap();
    symlink(&target, config_dir.join("config.toml")).unwrap();

    assert!(RouteConfig::load(&config_dir).is_err());
    assert_eq!(fs::read_to_string(target).unwrap(), original);
}

#[test]
fn save_rejects_symlinked_config_without_changing_target() {
    let root = TestDir::new("save-symlink");
    let config_dir = root.path().join("config");
    fs::create_dir(&config_dir).unwrap();
    let target = root.path().join("target.toml");
    let original = "external file must remain unchanged\n";
    fs::write(&target, original).unwrap();
    symlink(&target, config_dir.join("config.toml")).unwrap();

    assert!(RouteConfig::default().save(&config_dir).is_err());
    assert_eq!(fs::read_to_string(target).unwrap(), original);
    assert!(
        fs::symlink_metadata(config_dir.join("config.toml"))
            .unwrap()
            .file_type()
            .is_symlink()
    );
}

#[test]
fn concurrent_saves_use_unique_temporary_files_and_publish_complete_config() {
    let root = TestDir::new("concurrent");
    let config_dir = root.path().join("config");
    fs::create_dir(&config_dir).unwrap();
    fs::create_dir(config_dir.join(".config.toml.tmp")).unwrap();

    let direct = RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap();
    let webvpn = RouteConfig::parse("[route]\ndefault = \"webvpn\"\n").unwrap();
    let expected = [direct.to_toml(), webvpn.to_toml()];
    let barrier = Arc::new(Barrier::new(8));
    let mut threads = Vec::new();

    for index in 0..8 {
        let config_dir = config_dir.clone();
        let barrier = Arc::clone(&barrier);
        let config = if index % 2 == 0 {
            direct.clone()
        } else {
            webvpn.clone()
        };
        threads.push(std::thread::spawn(move || {
            barrier.wait();
            config.save(config_dir)
        }));
    }

    for thread in threads {
        thread.join().expect("save thread panicked").unwrap();
    }

    let published = fs::read_to_string(config_dir.join("config.toml")).unwrap();
    assert!(expected.contains(&published));
    RouteConfig::parse(&published).expect("published config must parse completely");

    let leftovers = fs::read_dir(&config_dir)
        .unwrap()
        .map(|entry| entry.unwrap().file_name())
        .filter(|name| name.to_string_lossy().starts_with(".config.toml.tmp."))
        .collect::<Vec<_>>();
    assert!(
        leftovers.is_empty(),
        "temporary files remain: {leftovers:?}"
    );

    assert_eq!(
        fs::metadata(config_dir.join("config.toml"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
    assert_eq!(
        fs::metadata(&config_dir).unwrap().permissions().mode() & 0o777,
        0o700
    );
}
