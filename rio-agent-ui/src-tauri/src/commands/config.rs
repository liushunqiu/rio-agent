use tauri::State;
use serde::{Deserialize, Serialize};

use crate::state::AppState;
use rio_storage::Configuration;

#[derive(Debug, Serialize, Deserialize)]
pub struct ConfigInfo {
    pub id: String,
    pub name: String,
    pub provider: String,
    pub model: String,
    pub endpoint: Option<String>,
    pub is_active: bool,
}

impl From<Configuration> for ConfigInfo {
    fn from(config: Configuration) -> Self {
        Self {
            id: config.id,
            name: config.name,
            provider: config.provider,
            model: config.model,
            endpoint: config.endpoint,
            is_active: config.is_active,
        }
    }
}

/// 列出所有配置
#[tauri::command]
pub async fn list_configurations(
    state: State<'_, AppState>,
) -> Result<Vec<ConfigInfo>, String> {
    let configs = state
        .storage
        .list_configurations()
        .await
        .map_err(|e| e.to_string())?;

    Ok(configs.into_iter().map(ConfigInfo::from).collect())
}

/// 创建配置
#[tauri::command]
pub async fn create_configuration(
    name: String,
    provider: String,
    model: String,
    endpoint: Option<String>,
    state: State<'_, AppState>,
) -> Result<String, String> {
    let config = state
        .storage
        .create_configuration(&name, &provider, &model, endpoint.as_deref())
        .await
        .map_err(|e| e.to_string())?;

    Ok(config.id)
}

/// 获取激活的配置
#[tauri::command]
pub async fn get_active_configuration(
    state: State<'_, AppState>,
) -> Result<Option<ConfigInfo>, String> {
    let config = state
        .storage
        .get_active_configuration()
        .await
        .map_err(|e| e.to_string())?;

    Ok(config.map(ConfigInfo::from))
}

/// 设置激活配置
#[tauri::command]
pub async fn set_active_configuration(
    config_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state
        .storage
        .set_active_configuration(&config_id)
        .await
        .map_err(|e| e.to_string())
}

/// 删除配置
#[tauri::command]
pub async fn delete_configuration(
    config_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state
        .storage
        .delete_configuration(&config_id)
        .await
        .map_err(|e| e.to_string())
}

/// 更新会话标题
#[tauri::command]
pub async fn update_conversation_title(
    conversation_id: String,
    title: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state
        .storage
        .update_session_title(&conversation_id, &title)
        .await
        .map_err(|e| e.to_string())
}
