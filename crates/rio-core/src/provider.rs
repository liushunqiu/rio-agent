use crate::message::Message;
use anyhow::Result;
use serde_json::Value;

pub struct StreamChunk {
    pub content: String,
    pub is_tool_call: bool,
    pub tool_call_data: Option<Value>,
}

#[async_trait::async_trait]
pub trait AIProvider: Send + Sync {
    async fn send_message(
        &self,
        messages: &[Message],
        tools: Option<Vec<Value>>,
    ) -> Result<Message>;

    async fn stream_message(
        &self,
        messages: &[Message],
        tools: Option<Vec<Value>>,
    ) -> Result<tokio::sync::mpsc::Receiver<Result<StreamChunk>>>;

    fn model_name(&self) -> &str;

    fn supports_thinking(&self) -> bool {
        false
    }

    fn supports_vision(&self) -> bool {
        false
    }
}
