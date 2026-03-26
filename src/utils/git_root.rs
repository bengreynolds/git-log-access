use anyhow::{Context, Result};
use std::env;
use std::path::{Path, PathBuf};

/// Find the git repository root directory from a given path
/// Returns the absolute path to the git repository root, or None if not in a git repository
pub fn find_git_root<P: AsRef<Path>>(start_path: P) -> Option<PathBuf> {
    let mut current = canonicalize_for_logging(start_path.as_ref()).ok()?;

    loop {
        let git_dir = current.join(".git");
        if git_dir.exists() {
            return Some(current);
        }

        match current.parent() {
            Some(parent) => current = parent.to_path_buf(),
            None => return None,
        }
    }
}

/// Find git repository root from current working directory
pub fn find_git_root_cwd() -> Option<PathBuf> {
    let cwd = env::current_dir().ok()?;
    find_git_root(cwd)
}

/// Check if a path is within a git repository
pub fn is_git_repository<P: AsRef<Path>>(path: P) -> bool {
    find_git_root(path).is_some()
}

/// Extract repository name from git root path
pub fn get_repository_name<P: AsRef<Path>>(git_root: P) -> Option<String> {
    git_root
        .as_ref()
        .file_name()?
        .to_str()
        .map(|s| s.to_string())
}

/// Normalize path for consistent logging (convert to forward slashes, resolve relative paths)
pub fn normalize_path<P: AsRef<Path>>(path: P) -> Result<String> {
    let canonical = canonicalize_for_logging(path.as_ref())
        .with_context(|| format!("Failed to canonicalize path: {:?}", path.as_ref()))?;

    let path_str = canonical
        .to_str()
        .context("Path contains invalid UTF-8 characters")?;

    #[cfg(windows)]
    let normalized = path_str.replace('\\', "/");
    #[cfg(unix)]
    let normalized = path_str.to_string();

    Ok(normalized)
}

/// Resolve relative paths and working directory references
pub fn resolve_path_context<P: AsRef<Path>, W: AsRef<Path>>(
    path: P,
    working_dir: Option<W>,
) -> Result<PathBuf> {
    let path = path.as_ref();

    if path.is_absolute() {
        return Ok(path.to_path_buf());
    }

    let base_dir = if let Some(wd) = working_dir {
        wd.as_ref().to_path_buf()
    } else {
        env::current_dir().context("Failed to get current directory")?
    };

    Ok(base_dir.join(path))
}

fn canonicalize_for_logging(path: &Path) -> Result<PathBuf> {
    let canonical = path.canonicalize()?;
    Ok(strip_windows_verbatim_prefix(canonical))
}

#[cfg(windows)]
fn strip_windows_verbatim_prefix(path: PathBuf) -> PathBuf {
    let raw = path.as_os_str().to_string_lossy();

    if let Some(stripped) = raw.strip_prefix(r"\\?\") {
        PathBuf::from(stripped)
    } else {
        path
    }
}

#[cfg(not(windows))]
fn strip_windows_verbatim_prefix(path: PathBuf) -> PathBuf {
    path
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn create_test_git_repo() -> TempDir {
        let temp_dir = TempDir::new().unwrap();
        let git_dir = temp_dir.path().join(".git");
        fs::create_dir(&git_dir).unwrap();
        fs::write(
            git_dir.join("config"),
            "[core]\n\trepositoryformatversion = 0\n",
        )
        .unwrap();
        temp_dir
    }

    #[test]
    fn test_find_git_root() {
        let test_repo = create_test_git_repo();
        let repo_path = test_repo.path();

        let root = find_git_root(repo_path);
        assert!(root.is_some());
        assert_eq!(root.unwrap(), repo_path);

        let subdir = repo_path.join("src");
        fs::create_dir(&subdir).unwrap();
        let root = find_git_root(&subdir);
        assert!(root.is_some());
        assert_eq!(root.unwrap(), repo_path);
    }

    #[test]
    fn test_find_git_root_no_repo() {
        let temp_dir = TempDir::new().unwrap();
        let root = find_git_root(temp_dir.path());
        assert!(root.is_none());
    }

    #[test]
    fn test_is_git_repository() {
        let test_repo = create_test_git_repo();
        assert!(is_git_repository(test_repo.path()));

        let temp_dir = TempDir::new().unwrap();
        assert!(!is_git_repository(temp_dir.path()));
    }

    #[test]
    fn test_get_repository_name() {
        let test_repo = create_test_git_repo();
        let repo_name = get_repository_name(test_repo.path());
        assert!(repo_name.is_some());
        assert!(repo_name.unwrap().contains("tmp"));
    }

    #[test]
    fn test_normalize_path() {
        let temp_dir = TempDir::new().unwrap();
        let normalized = normalize_path(temp_dir.path()).unwrap();
        assert!(!normalized.is_empty());
        assert!(!normalized.contains('\\'));
    }
}
