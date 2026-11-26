use std::io;
use std::path::{Path, PathBuf};

use ubaa_core::facade::{RawDiagnostics, UbaaClient};

pub(crate) struct DiagnosticsExport {
    path: PathBuf,
    recorder: RawDiagnostics,
}

impl DiagnosticsExport {
    pub(crate) fn start(path: Option<PathBuf>, client: &UbaaClient) -> Option<Self> {
        path.map(|path| {
            let recorder = client.raw_diagnostics();
            recorder.enable();
            Self { path, recorder }
        })
    }

    pub(crate) fn finish(self) -> io::Result<()> {
        write_file(&self.path, &self.recorder.export_json())
    }
}

#[cfg(unix)]
pub(crate) fn prepare_path(repo: &Path, requested: &Path) -> io::Result<PathBuf> {
    use std::fs::{self, DirBuilder};
    use std::os::unix::fs::{DirBuilderExt as _, PermissionsExt as _};
    use std::path::Component;

    let invalid = || io::Error::from(io::ErrorKind::InvalidInput);
    if requested
        .components()
        .any(|part| part == Component::ParentDir)
    {
        return Err(invalid());
    }
    let repo = repo.canonicalize()?;
    let path = repo.join(requested);
    let relative = path.strip_prefix(&repo).map_err(|_| invalid())?;
    let filename = relative
        .strip_prefix(".ubaa_local")
        .map_err(|_| invalid())?
        .file_name()
        .ok_or_else(invalid)?;
    let mut directory = repo;
    for part in relative.parent().ok_or_else(invalid)? {
        directory.push(part);
        let metadata = match fs::symlink_metadata(&directory) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                DirBuilder::new().mode(0o700).create(&directory)?;
                fs::symlink_metadata(&directory)?
            }
            Err(error) => return Err(error),
        };
        if !metadata.is_dir() || metadata.permissions().mode() & 0o777 != 0o700 {
            return Err(invalid());
        }
    }
    let file = directory.join(filename);
    match fs::symlink_metadata(&file) {
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(file),
        Err(error) => Err(error),
        Ok(_) => Err(io::Error::from(io::ErrorKind::AlreadyExists)),
    }
}

#[cfg(unix)]
fn write_file(path: &Path, json: &str) -> io::Result<()> {
    use std::fs::{OpenOptions, Permissions};
    use std::io::Write as _;
    use std::os::unix::fs::{OpenOptionsExt as _, PermissionsExt as _};

    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)?;
    file.set_permissions(Permissions::from_mode(0o600))?;
    file.write_all(json.as_bytes())
}

#[cfg(not(unix))]
pub(crate) fn prepare_path(_repo: &Path, _requested: &Path) -> io::Result<PathBuf> {
    Err(io::Error::from(io::ErrorKind::Unsupported))
}

#[cfg(not(unix))]
fn write_file(_path: &Path, _json: &str) -> io::Result<()> {
    Err(io::Error::from(io::ErrorKind::Unsupported))
}

#[cfg(all(test, unix))]
#[path = "../tests/diagnostics/mod.rs"]
mod tests;
