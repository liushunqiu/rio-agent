use crate::{message::Message, provider::AIProvider, tool::ToolRegistry};
use anyhow::{anyhow, Result};
use std::sync::Arc;
use tokio::sync::mpsc;
use futures_util::stream::Stream;
use std::pin::Pin;

pub struct AgentEngine {
    provider: Arc<dyn AIProvider>,
    tools: Arc<ToolRegistry>,
    max_iterations: usize,
}

impl AgentEngine {
    pub fn new(provider: Arc<dyn AIProvider>, tools: Arc<ToolRegistry>) -> Self {
        Self {
            provider,
            tools,
            max_iterations: 20,
        }
    }

    pub fn with_max_iterations(mut self, max: usize) -> Self {
        self.max_iterations = max;
        self
    }

    pub async fn run(&self, messages: &mut Vec<Message>) -> Result<Message> {
        let mut iterations = 0;

        loop {
            if iterations >= self.max_iterations {
                return Err(anyhow!("Max iterations ({}) reached", self.max_iterations));
            }
            iterations += 1;

            let tools_schema = if !self.tools.all().is_empty() {
                Some(self.tools.tools_schema())
            } else {
                None
            };

            let response = self.provider.send_message(messages, tools_schema).await?;

            if let Some(tool_calls) = &response.tool_calls {
                messages.push(response.clone());

                for tool_call in tool_calls {
                    let tool = self
                        .tools
                        .get(&tool_call.name)
                        .ok_or_else(|| anyhow!("Unknown tool: {}", tool_call.name))?;

                    let result = tool.execute(tool_call.arguments.clone()).await?;

                    messages.push(Message::new_tool_result(tool_call.id.clone(), result));
                }
            } else {
                messages.push(response.clone());
                return Ok(response);
            }
        }
    }

    /// Run the agent with streaming output
    /// Returns a stream of text chunks as they arrive from the AI provider
    pub async fn run_streaming(
        &self,
        messages: Vec<Message>,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<String>> + Send>>> {
        let (tx, rx) = mpsc::channel(100);
        let provider = self.provider.clone();
        let tools = self.tools.clone();
        let max_iterations = self.max_iterations;

        tokio::spawn(async move {
            let mut messages = messages;
            let mut _iterations = 0;

            loop {
                if _iterations >= max_iterations {
                    let _ = tx.send(Err(anyhow!("Max iterations ({}) reached", max_iterations))).await;
                    break;
                }
                _iterations += 1;

                let tools_schema = if !tools.all().is_empty() {
                    Some(tools.tools_schema())
                } else {
                    None
                };

                // Get streaming response
                let mut stream_rx = match provider.stream_message(&messages, tools_schema).await {
                    Ok(rx) => rx,
                    Err(e) => {
                        let _ = tx.send(Err(e)).await;
                        break;
                    }
                };

                let mut full_content = String::new();
                let mut has_tool_calls = false;

                // Stream chunks to the output
                while let Some(chunk_result) = stream_rx.recv().await {
                    match chunk_result {
                        Ok(chunk) => {
                            if chunk.is_tool_call {
                                has_tool_calls = true;
                                // Tool calls are not streamed to user
                            } else {
                                full_content.push_str(&chunk.content);
                                if tx.send(Ok(chunk.content)).await.is_err() {
                                    // Receiver dropped
                                    return;
                                }
                            }
                        }
                        Err(e) => {
                            let _ = tx.send(Err(e)).await;
                            return;
                        }
                    }
                }

                // Create response message
                let response = Message::new_assistant(full_content);

                // If there are tool calls, execute them and continue
                if has_tool_calls {
                    // TODO: Handle tool calls in streaming mode
                    // For now, just break
                    break;
                } else {
                    messages.push(response);
                    break;
                }
            }
        });

        Ok(Box::pin(tokio_stream::wrappers::ReceiverStream::new(rx)))
    }
}
