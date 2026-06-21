use tauri::{State, Window, Emitter};
use serde::{Deserialize, Serialize};
use futures_util::StreamExt;

use crate::state::AppState;
use rio_core::{Message, Role};
use rio_storage::Session;

#[derive(Debug, Serialize, Deserialize)]
pub struct ConversationInfo {
    pub id: String,
    pub title: String,
    pub created_at: String,
    pub updated_at: String,
}

impl From<Session> for ConversationInfo {
    fn from(session: Session) -> Self {
        Self {
            id: session.id,
            title: session.title,
            created_at: session.created_at.to_rfc3339(),
            updated_at: session.updated_at.to_rfc3339(),
        }
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub struct MessageInfo {
    pub id: String,
    pub role: String,
    pub content: String,
    pub timestamp: String,
}

impl From<Message> for MessageInfo {
    fn from(msg: Message) -> Self {
        let role = match msg.role {
            Role::User => "user",
            Role::Assistant => "assistant",
            Role::System => "system",
        };
        Self {
            id: msg.id,
            role: role.to_string(),
            content: msg.content,
            timestamp: msg.created_at.to_rfc3339(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageChunk {
    pub conversation_id: String,
    pub content: String,
}

/// 发送消息（流式）
#[tauri::command]
pub async fn send_message(
    conversation_id: String,
    content: String,
    state: State<'_, AppState>,
    window: Window,
) -> Result<String, String> {
    let engine = state
        .get_or_create_engine(&conversation_id)
        .await
        .map_err(|e| e.to_string())?;

    // 创建用户消息
    let user_message = Message::new_user(content.clone());

    // 保存用户消息
    state
        .storage
        .save_message(&conversation_id, &user_message)
        .await
        .map_err(|e| e.to_string())?;

    // 获取流式响应
    let mut stream = engine
        .run_streaming(vec![user_message])
        .await
        .map_err(|e| e.to_string())?;

    // 累积响应内容
    let mut full_response = String::new();

    // 流式发送到前端
    while let Some(chunk_result) = stream.next().await {
        match chunk_result {
            Ok(chunk) => {
                full_response.push_str(&chunk);
                let payload = MessageChunk {
                    conversation_id: conversation_id.clone(),
                    content: chunk,
                };
                window.emit("message_chunk", payload)
                    .map_err(|e| e.to_string())?;
            }
            Err(e) => {
                window.emit("message_error", e.to_string())
                    .map_err(|e| e.to_string())?;
                return Err(e.to_string());
            }
        }
    }

    // 保存助手响应
    let assistant_message = Message::new_assistant(full_response);
    state
        .storage
        .save_message(&conversation_id, &assistant_message)
        .await
        .map_err(|e| e.to_string())?;

    Ok("Message sent successfully".to_string())
}

/// 列出所有对话
#[tauri::command]
pub async fn list_conversations(
    state: State<'_, AppState>,
) -> Result<Vec<ConversationInfo>, String> {
    let sessions = state
        .storage
        .list_sessions()
        .await
        .map_err(|e| e.to_string())?;

    Ok(sessions.into_iter().map(ConversationInfo::from).collect())
}

/// 创建新对话
#[tauri::command]
pub async fn create_conversation(
    state: State<'_, AppState>,
) -> Result<String, String> {
    let session = state
        .storage
        .create_session("New Conversation")
        .await
        .map_err(|e| e.to_string())?;

    Ok(session.id)
}

/// 删除对话
#[tauri::command]
pub async fn delete_conversation(
    conversation_id: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    // 移除缓存的引擎
    state.remove_engine(&conversation_id).await;

    // TODO: 实现数据库删除
    // state.storage.delete_session(&conversation_id).await
    //     .map_err(|e| e.to_string())

    Ok(())
}

/// 获取对话的所有消息
#[tauri::command]
pub async fn get_conversation_messages(
    conversation_id: String,
    state: State<'_, AppState>,
) -> Result<Vec<MessageInfo>, String> {
    let messages = state
        .storage
        .get_messages(&conversation_id)
        .await
        .map_err(|e| e.to_string())?;

    Ok(messages.into_iter().map(MessageInfo::from).collect())
}
