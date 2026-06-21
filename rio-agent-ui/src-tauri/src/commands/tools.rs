use tauri::State;
use serde::{Deserialize, Serialize};

use crate::state::AppState;

#[derive(Debug, Serialize, Deserialize)]
pub struct ToolInfo {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

/// 列出所有工具
#[tauri::command]
pub async fn list_tools(
    state: State<'_, AppState>,
) -> Result<Vec<ToolInfo>, String> {
    let tools = state.tool_registry.all();
    Ok(tools
        .iter()
        .map(|tool| ToolInfo {
            name: tool.name().to_string(),
            description: tool.description().to_string(),
            parameters: tool.parameters(),
        })
        .collect())
}

/// 执行工具
#[tauri::command]
pub async fn execute_tool(
    tool_name: String,
    args: serde_json::Value,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let tool = state
        .tool_registry
        .get(&tool_name)
        .ok_or_else(|| format!("Tool not found: {}", tool_name))?;

    tool.execute(args)
        .await
        .map_err(|e| e.to_string())
}
