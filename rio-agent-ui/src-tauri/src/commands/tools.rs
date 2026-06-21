use tauri::State;
use serde::{Deserialize, Serialize};

use crate::state::AppState;
use rio_core::Tool;

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
    let tools = state.tool_registry.list_tools();
    Ok(tools
        .into_iter()
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
    state
        .tool_registry
        .execute(&tool_name, args)
        .await
        .map_err(|e| e.to_string())
}
