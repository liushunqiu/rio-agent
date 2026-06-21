use anyhow::{anyhow, Result, Context};
use rio_core::Tool;
use serde::Deserialize;
use serde_json::Value;
use std::path::{Path, PathBuf};
use tokio::fs;

/// Validates that a path is safe to access (no path traversal, no sensitive files)
fn validate_path(path: &Path) -> Result<PathBuf> {
    // Get current working directory as base
    let base_dir = std::env::current_dir()
        .context("Failed to get current directory")?;

    // Expand ~ to home directory if needed
    let expanded_path = if path.starts_with("~") {
        let home = std::env::var("HOME")
            .or_else(|_| std::env::var("USERPROFILE"))
            .context("Cannot determine home directory")?;
        PathBuf::from(home).join(path.strip_prefix("~").unwrap())
    } else {
        path.to_path_buf()
    };

    // Convert to absolute path
    let absolute_path = if expanded_path.is_absolute() {
        expanded_path
    } else {
        base_dir.join(expanded_path)
    };

    // Canonicalize to resolve .. and symlinks
    let canonical = absolute_path.canonicalize()
        .or_else(|_| {
            // If file doesn't exist yet (for write operations), canonicalize parent
            if let Some(parent) = absolute_path.parent() {
                let canonical_parent = parent.canonicalize()
                    .context("Parent directory does not exist")?;
                Ok(canonical_parent.join(absolute_path.file_name().unwrap()))
            } else {
                Err(anyhow!("Invalid path: {}", absolute_path.display()))
            }
        })?;

    // Check if path is within working directory (allow current dir and subdirs)
    if !canonical.starts_with(&base_dir) {
        return Err(anyhow!(
            "Path traversal blocked: {} is outside working directory {}",
            canonical.display(),
            base_dir.display()
        ));
    }

    // Block sensitive file patterns
    let path_str = canonical.to_string_lossy();
    let blocked_patterns = [
        "/etc/", "/.ssh/", "/.aws/", "/.gnupg/",
        "/System/", "/Windows/System32/",
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        "authorized_keys", ".env", "credentials"
    ];

    for pattern in blocked_patterns {
        if path_str.contains(pattern) {
            return Err(anyhow!(
                "Access to sensitive path blocked: {}",
                canonical.display()
            ));
        }
    }

    Ok(canonical)
}

pub struct ReadFileTool;

#[derive(Deserialize)]
struct ReadFileArgs {
    path: String,
}

#[async_trait::async_trait]
impl Tool for ReadFileTool {
    fn name(&self) -> &str {
        "read_file"
    }

    fn description(&self) -> &str {
        "Read the contents of a file at the specified path"
    }

    fn parameters(&self) -> Value {
        serde_json::json!({
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "The file path to read"
                }
            },
            "required": ["path"]
        })
    }

    async fn execute(&self, arguments: Value) -> Result<String> {
        let args: ReadFileArgs = serde_json::from_value(arguments)?;
        let path = PathBuf::from(&args.path);

        // Validate path for security
        let safe_path = validate_path(&path)?;

        // Check if file exists (async)
        let metadata = fs::metadata(&safe_path).await
            .map_err(|_| anyhow!("File not found: {}", args.path))?;

        if !metadata.is_file() {
            return Err(anyhow!("Path is not a file: {}", args.path));
        }

        let content = fs::read_to_string(&safe_path).await?;
        Ok(content)
    }
}

pub struct WriteFileTool;

#[derive(Deserialize)]
struct WriteFileArgs {
    path: String,
    content: String,
}

#[async_trait::async_trait]
impl Tool for WriteFileTool {
    fn name(&self) -> &str {
        "write_file"
    }

    fn description(&self) -> &str {
        "Write content to a file at the specified path, creating or overwriting it"
    }

    fn parameters(&self) -> Value {
        serde_json::json!({
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "The file path to write to"
                },
                "content": {
                    "type": "string",
                    "description": "The content to write"
                }
            },
            "required": ["path", "content"]
        })
    }

    async fn execute(&self, arguments: Value) -> Result<String> {
        let args: WriteFileArgs = serde_json::from_value(arguments)?;
        let path = PathBuf::from(&args.path);

        // Validate path for security
        let safe_path = validate_path(&path)?;

        // Create parent directories if needed
        if let Some(parent) = safe_path.parent() {
            fs::create_dir_all(parent).await?;
        }

        fs::write(&safe_path, &args.content).await?;
        Ok(format!("Successfully wrote {} bytes to {}", args.content.len(), args.path))
    }
}

pub struct ListDirectoryTool;

#[derive(Deserialize)]
struct ListDirectoryArgs {
    path: String,
}

#[async_trait::async_trait]
impl Tool for ListDirectoryTool {
    fn name(&self) -> &str {
        "list_directory"
    }

    fn description(&self) -> &str {
        "List files and directories in the specified path"
    }

    fn parameters(&self) -> Value {
        serde_json::json!({
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "The directory path to list"
                }
            },
            "required": ["path"]
        })
    }

    async fn execute(&self, arguments: Value) -> Result<String> {
        let args: ListDirectoryArgs = serde_json::from_value(arguments)?;
        let path = PathBuf::from(&args.path);

        // Validate path for security
        let safe_path = validate_path(&path)?;

        // Check if directory exists (async)
        let metadata = fs::metadata(&safe_path).await
            .map_err(|_| anyhow!("Directory not found: {}", args.path))?;

        if !metadata.is_dir() {
            return Err(anyhow!("Path is not a directory: {}", args.path));
        }

        let mut entries = fs::read_dir(&safe_path).await?;
        let mut result = Vec::new();

        while let Some(entry) = entries.next_entry().await? {
            let metadata = entry.metadata().await?;
            let name = entry.file_name().to_string_lossy().to_string();
            let entry_type = if metadata.is_dir() { "dir" } else { "file" };
            result.push(format!("{} ({})", name, entry_type));
        }

        result.sort();
        Ok(result.join("\n"))
    }
}
