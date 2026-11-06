//! Small durable files under the data dir: append-only JSON-lines tables and atomically replaced JSON documents.
//!
//! Every table is an append-only log of records; loading folds them (last record for a key wins). A torn last line
//! (crash mid-write) is ignored, so a crash never corrupts what was already written.

use serde::de::DeserializeOwned;
use serde::Serialize;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

const NL: u8 = 0x0a;

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("{path}: {source}")]
    Io {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("{path} line {line}: {source}")]
    Corrupt {
        path: PathBuf,
        line: usize,
        source: serde_json::Error,
    },
}

fn io(path: &Path) -> impl FnOnce(std::io::Error) -> StoreError + '_ {
    move |source| StoreError::Io {
        path: path.to_path_buf(),
        source,
    }
}

/// An append-only JSON-lines file.
#[derive(Debug)]
pub struct JsonLines {
    path: PathBuf,
    file: File,
}

impl JsonLines {
    /// Opens (creating it and its directory if needed) and returns every complete record in order.
    pub fn open<T: DeserializeOwned>(
        path: impl Into<PathBuf>,
    ) -> Result<(JsonLines, Vec<T>), StoreError> {
        let path = path.into();
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir).map_err(io(dir))?;
        }
        let raw = match fs::read(&path) {
            Ok(raw) => raw,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Vec::new(),
            Err(e) => return Err(StoreError::Io { path, source: e }),
        };
        // Everything up to the last newline is complete records. Bytes after it are a torn append (a crash mid-write)
        // unless they happen to parse; a torn tail is cut off so the next append starts on a clean line.
        let complete = raw
            .iter()
            .rposition(|b| *b == NL)
            .map(|i| i + 1)
            .unwrap_or(0);
        let mut records = Vec::new();
        for (i, line) in raw[..complete].split(|b| *b == NL).enumerate() {
            if line.iter().all(u8::is_ascii_whitespace) {
                continue;
            }
            match serde_json::from_slice(line) {
                Ok(r) => records.push(r),
                Err(source) => {
                    return Err(StoreError::Corrupt {
                        path,
                        line: i + 1,
                        source,
                    })
                }
            }
        }
        let tail = &raw[complete..];
        let mut keep_tail = false;
        if !tail.iter().all(u8::is_ascii_whitespace) {
            match serde_json::from_slice(tail) {
                Ok(r) => {
                    records.push(r);
                    keep_tail = true;
                }
                Err(_) => tracing::warn!(path = %path.display(), "dropping a torn last line"),
            }
        }
        if !keep_tail && complete < raw.len() {
            let f = OpenOptions::new()
                .write(true)
                .open(&path)
                .map_err(io(&path))?;
            f.set_len(complete as u64).map_err(io(&path))?;
            f.sync_all().map_err(io(&path))?;
        }
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .map_err(io(&path))?;
        if keep_tail {
            file.write_all(&[NL]).map_err(io(&path))?;
        }
        Ok((JsonLines { path, file }, records))
    }

    /// Appends one record and flushes it to disk before returning.
    pub fn append<T: Serialize>(&mut self, record: &T) -> Result<(), StoreError> {
        let mut line = serde_json::to_vec(record).expect("records always serialize");
        line.push(NL);
        self.file.write_all(&line).map_err(io(&self.path))?;
        self.file.sync_data().map_err(io(&self.path))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

/// Reads a JSON document, `None` when it doesn't exist.
pub fn read_json<T: DeserializeOwned>(path: &Path) -> Result<Option<T>, StoreError> {
    match fs::read(path) {
        Ok(raw) => serde_json::from_slice(&raw)
            .map(Some)
            .map_err(|source| StoreError::Corrupt {
                path: path.to_path_buf(),
                line: 1,
                source,
            }),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(StoreError::Io {
            path: path.to_path_buf(),
            source: e,
        }),
    }
}

/// Replaces a JSON document atomically (write a temp file, sync, rename over).
pub fn write_json<T: Serialize>(path: &Path, value: &T) -> Result<(), StoreError> {
    if let Some(dir) = path.parent() {
        fs::create_dir_all(dir).map_err(io(dir))?;
    }
    let tmp = path.with_extension("tmp");
    {
        let mut f = File::create(&tmp).map_err(io(&tmp))?;
        f.write_all(&serde_json::to_vec_pretty(value).expect("documents always serialize"))
            .map_err(io(&tmp))?;
        f.sync_all().map_err(io(&tmp))?;
    }
    fs::rename(&tmp, path).map_err(io(path))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Debug, PartialEq, Serialize, Deserialize)]
    struct R {
        k: String,
        v: u32,
    }

    #[test]
    fn appends_survive_reopen_and_torn_tail() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("sub/t.jsonl");
        {
            let (mut t, rs) = JsonLines::open::<R>(&p).unwrap();
            assert!(rs.is_empty());
            t.append(&R {
                k: "a".into(),
                v: 1,
            })
            .unwrap();
            t.append(&R {
                k: "b".into(),
                v: 2,
            })
            .unwrap();
        }
        // Simulate a crash mid-append.
        let mut f = OpenOptions::new().append(true).open(&p).unwrap();
        f.write_all(b"{\"k\":\"c\",\"v\"").unwrap();
        drop(f);
        {
            let (mut t, rs) = JsonLines::open::<R>(&p).unwrap();
            assert_eq!(rs.len(), 2);
            t.append(&R {
                k: "d".into(),
                v: 4,
            })
            .unwrap();
        }
        let (_, rs) = JsonLines::open::<R>(&p).unwrap();
        assert_eq!(rs.iter().map(|r| r.v).collect::<Vec<_>>(), vec![1, 2, 4]);
    }

    #[test]
    fn corruption_in_the_middle_is_an_error() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("t.jsonl");
        fs::write(
            &p,
            "{\"k\":\"a\",\"v\":1}\ngarbage\n{\"k\":\"b\",\"v\":2}\n",
        )
        .unwrap();
        assert!(matches!(
            JsonLines::open::<R>(&p),
            Err(StoreError::Corrupt { line: 2, .. })
        ));
    }

    #[test]
    fn json_documents_replace_atomically() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("c.json");
        assert_eq!(read_json::<R>(&p).unwrap(), None);
        write_json(
            &p,
            &R {
                k: "x".into(),
                v: 9,
            },
        )
        .unwrap();
        write_json(
            &p,
            &R {
                k: "x".into(),
                v: 10,
            },
        )
        .unwrap();
        assert_eq!(
            read_json::<R>(&p).unwrap(),
            Some(R {
                k: "x".into(),
                v: 10
            })
        );
        assert!(!p.with_extension("tmp").exists());
    }
}
