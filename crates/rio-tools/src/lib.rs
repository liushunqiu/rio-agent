pub mod file;
pub mod command;

pub use file::{ReadFileTool, WriteFileTool, ListDirectoryTool};
pub use command::ExecuteCommandTool;

use rio_core::ToolRegistry;

pub fn register_default_tools(registry: &mut ToolRegistry) {
    registry.register(Box::new(ReadFileTool));
    registry.register(Box::new(WriteFileTool));
    registry.register(Box::new(ListDirectoryTool));
    registry.register(Box::new(ExecuteCommandTool));
}
