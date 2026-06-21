use anyhow::{Result, anyhow};
use rio_core::Tool;
use serde::Deserialize;
use serde_json::Value;
use tokio::process::Command;

pub struct ExecuteCommandTool;

#[derive(Deserialize)]
struct ExecuteCommandArgs {
    command: String,
}

#[async_trait::async_trait]
impl Tool for ExecuteCommandTool {
    fn name(&self) -> &str {
        "execute_command"
    }

    fn description(&self) -> &str {
        "Execute a shell command and return its output"
    }

    fn parameters(&self) -> Value {
        serde_json::json!({
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "The shell command to execute"
                }
            },
            "required": ["command"]
        })
    }

    async fn execute(&self, arguments: Value) -> Result<String> {
        let args: ExecuteCommandArgs = serde_json::from_value(arguments)?;

        #[cfg(unix)]
        let output = Command::new("sh")
            .arg("-c")
            .arg(&args.command)
            .output()
            .await?;

        #[cfg(windows)]
        let output = Command::new("powershell")
            .arg("-Command")
            .arg(&args.command)
            .output()
            .await?;

        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);

        if output.status.success() {
            Ok(stdout.to_string())
        } else {
            Err(anyhow!(
                "Command failed with exit code {:?}\nStdout: {}\nStderr: {}",
                output.status.code(), stdout, stderr
            ))
        }
    }
}
