use std::{
    env,
    fs::{self, create_dir, create_dir_all},
    io,
    ops::Deref,
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

static NEXT_RUN: AtomicU64 = AtomicU64::new(0);

pub struct TestTempDir(PathBuf);

impl TestTempDir {
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Deref for TestTempDir {
    type Target = Path;

    fn deref(&self) -> &Self::Target {
        self.path()
    }
}

impl AsRef<Path> for TestTempDir {
    fn as_ref(&self) -> &Path {
        self.path()
    }
}

impl Drop for TestTempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// 创建位于测试临时根目录下的独立套件运行目录。
///
/// # Errors
///
/// 当根目录、套件目录或运行目录无法创建时返回文件系统错误。
pub fn test_temp_dir(suite: &str) -> io::Result<TestTempDir> {
    let root = env::var_os("UBAA_TEST_TMP")
        .filter(|path| !path.is_empty())
        .map_or_else(
            || PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/test_tmp"),
            PathBuf::from,
        );
    create_dir_all(&root)?;
    let root = root.canonicalize()?;
    let parent = root.join(suite);
    create_dir_all(&parent)?;

    loop {
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let sequence = NEXT_RUN.fetch_add(1, Ordering::Relaxed);
        let directory = parent.join(format!("run-{}-{timestamp}-{sequence}", std::process::id()));
        match create_dir(&directory) {
            Ok(()) => return Ok(TestTempDir(directory)),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {}
            Err(error) => return Err(error),
        }
    }
}
