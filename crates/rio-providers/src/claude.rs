use anyhow::{anyhow, Result};
use rio_core::{AIProvider, Message, Role, StreamChunk, ToolCall};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tokio::sync::mpsc;

pub struct ClaudeProvider {
    api_key: String,
    model: String,
    base_url: String,
    client: Client,
}

impl ClaudeProvider {
    pub fn new(api_key: String, model: String) -> Self {
        Self {
            api_key,
            model,
            base_url: "https://api.anthropic.com/v1".to_string(),
            client: Client::new(),
        }
    }

    pub fn with_base_url(mut self, url: String) -> Self {
        self.base_url = url;
        self
    }

    fn convert_messages(&self, messages: &[Message]) -> (Option<String>, Vec<ClaudeMessage>) {
        let mut system_prompt = None;
        let mut claude_messages = Vec::new();

        for msg in messages {
            match msg.role {
                Role::System => {
                    system_prompt = Some(msg.content.clone());
                }
                Role::User => {
                    if let Some(tool_call_id) = &msg.tool_call_id {
                        claude_messages.push(ClaudeMessage {
                            role: "user".to_string(),
                            content: vec![ClaudeContent::ToolResult {
                                tool_use_id: tool_call_id.clone(),
                                content: msg.content.clone(),
                            }],
                        });
                    } else {
                        claude_messages.push(ClaudeMessage {
                            role: "user".to_string(),
                            content: vec![ClaudeContent::Text {
                                text: msg.content.clone(),
                            }],
                        });
                    }
                }
                Role::Assistant => {
                    let mut content = vec![];

                    if !msg.content.is_empty() {
                        content.push(ClaudeContent::Text {
                            text: msg.content.clone(),
                        });
                    }

                    if let Some(tool_calls) = &msg.tool_calls {
                        for tc in tool_calls {
                            content.push(ClaudeContent::ToolUse {
                                id: tc.id.clone(),
                                name: tc.name.clone(),
                                input: tc.arguments.clone(),
                            });
                        }
                    }

                    claude_messages.push(ClaudeMessage {
                        role: "assistant".to_string(),
                        content,
                    });
                }
            }
        }

        (system_prompt, claude_messages)
    }
}

#[async_trait::async_trait]
impl AIProvider for ClaudeProvider {
    async fn send_message(
        &self,
        messages: &[Message],
        tools: Option<Vec<Value>>,
    ) -> Result<Message> {
        let (system, claude_messages) = self.convert_messages(messages);

        let mut request_body = serde_json::json!({
            "model": self.model,
            "messages": claude_messages,
            "max_tokens": 4096,
        });

        if let Some(sys) = system {
            request_body["system"] = Value::String(sys);
        }

        if let Some(tools_schema) = tools {
            request_body["tools"] = Value::Array(tools_schema);
        }

        let response = self
            .client
            .post(format!("{}/messages", self.base_url))
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&request_body)
            .send()
            .await?;

        if !response.status().is_success() {
            let error_text = response.text().await?;
            return Err(anyhow!("Claude API error: {}", error_text));
        }

        let response_data: ClaudeResponse = response.json().await?;

        let mut content = String::new();
        let mut tool_calls = Vec::new();

        for block in response_data.content {
            match block {
                ClaudeContent::Text { text } => {
                    content.push_str(&text);
                }
                ClaudeContent::ToolUse { id, name, input } => {
                    tool_calls.push(ToolCall {
                        id,
                        name,
                        arguments: input,
                    });
                }
                _ => {}
            }
        }

        let mut message = Message::new_assistant(content);
        if !tool_calls.is_empty() {
            message = message.with_tool_calls(tool_calls);
        }

        Ok(message)
    }

    async fn stream_message(
        &self,
        _messages: &[Message],
        _tools: Option<Vec<Value>>,
    ) -> Result<mpsc::Receiver<Result<StreamChunk>>> {
        let (_tx, rx) = mpsc::channel(100);
        Ok(rx)
    }

    fn model_name(&self) -> &str {
        &self.model
    }

    fn supports_thinking(&self) -> bool {
        self.model.contains("opus") || self.model.contains("sonnet-4")
    }

    fn supports_vision(&self) -> bool {
        true
    }
}

#[derive(Debug, Serialize)]
struct ClaudeMessage {
    role: String,
    content: Vec<ClaudeContent>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
enum ClaudeContent {
    Text {
        text: String,
    },
    ToolUse {
        id: String,
        name: String,
        input: Value,
    },
    ToolResult {
        tool_use_id: String,
        content: String,
    },
}

#[derive(Debug, Deserialize)]
struct ClaudeResponse {
    content: Vec<ClaudeContent>,
}
