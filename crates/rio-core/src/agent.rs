use crate::{message::Message, provider::AIProvider, tool::ToolRegistry};
use anyhow::{anyhow, Result};
use std::sync::Arc;

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
}
