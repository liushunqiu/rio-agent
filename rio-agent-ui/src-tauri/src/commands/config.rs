use tauri::State;
use serde::{Deserialize, Serialize};

use crate::state::AppState;

#[derive(Debug, Serialize, Deserialize)]
pub struct ConfigInfo {
    pub id: String,
    pub name: String,
    pub provider: String,
    pub model: String,
    pub is_active: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct SaveConfigRequest {
    pub name: String,
    pub provider: String,
    pub model: String,
    pub api_key: String,
    pub base_url: Option<String>,
}

/// 保存配置
/// TODO: 实现配置持久化
#[tauri::command]
pub async fn save_config(
    _request: SaveConfigRequest,
    _state: State<'_, AppState>,
) -> Result<String, String> {
    // 暂时返回占位 ID
    Ok(uuid::Uuid::new_v4().to_string())
}

/// 列出所有配置
/// TODO: 实现配置列表查询
#[tauri::command]
pub async fn list_configs(
    _state: State<'_, AppState>,
) -> Result<Vec<ConfigInfo>, String> {
    // 暂时返回空列表
    Ok(vec![])
}

/// 删除配置
/// TODO: 实现配置删除
#[tauri::command]
pub async fn delete_config(
    _config_id: String,
    _state: State<'_, AppState>,
) -> Result<(), String> {
    Ok(())
}
