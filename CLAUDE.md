# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rio Agent is a cross-platform AI programming assistant built with Rust. It supports multi-provider AI services, 8 built-in tools, multi-agent DAG-based execution, intelligent task planning, shared memory system, and Agent-to-Agent communication.

**Platform**: Cross-platform (macOS, Windows, Linux)
**Language**: Rust 1.75+
**Architecture**: Modular workspace with 9 crates

## Build Commands

```bash
# Development build
cargo build

# Run CLI
cargo run --bin rio-cli

# Run tests (69 tests, all passing)
cargo test

# Run tests with output
cargo test -- --nocapture

# Lint check (zero warnings required)
cargo clippy -- -D warnings

# Format code
cargo fmt

# Quick scripts
./quickstart.sh       # Unix/macOS
./quickstart.bat      # Windows
```

## Critical Project Rules

### Workspace Structure

This is a Cargo workspace with 9 crates in `crates/` directory. **Never** create files outside the workspace structure. All Rust code lives in `crates/*/src/`.

### Zero External Swift Dependencies

**This project has NO Swift code.** All references to Swift files, Xcode, SwiftUI, or macOS-specific APIs are historical artifacts. The project was migrated from Swift to Rust for cross-platform support.

### API Key Storage

- **API Keys**: Stored securely via `keyring` crate (uses OS-native secure storage)
- **Config Metadata**: Stored in SQLite via `rio-storage` crate
- Each configuration = one model instance (provider + endpoint + model + API key)

## Architecture

### Crate Organization

| Crate | Path | Purpose |
|-------|------|---------|
| **rio-core** | `crates/rio-core` | Agent engine, message types, conversation loop |
| **rio-providers** | `crates/rio-providers` | AI provider abstraction (Claude/OpenAI/Gemini/DeepSeek) |
| **rio-tools** | `crates/rio-tools` | 8 built-in tools (file ops, command execution, search) |
| **rio-storage** | `crates/rio-storage` | SQLite persistence layer |
| **rio-security** | `crates/rio-security` | Command risk classification, path validation |
| **rio-cli** | `crates/rio-cli` | Command-line interface |
| **rio-identity** | `crates/rio-identity` | Agent identity system (roles, capabilities) |
| **rio-router** | `crates/rio-router` | A2A routing, @mention parsing, deadlock prevention |
| **rio-memory** | `crates/rio-memory` | Shared memory (Evidence/Lessons/Decisions stores) |

### Execution Modes

Rio Agent has two execution engines:

#### 1. Single Agent (AgentEngine)

Default path for simple to moderate tasks (defined in `rio-core`):

1. **Message Handling** — User input → AI Provider → Tool calls
2. **Tool Execution** — Up to configurable iterations (default 100)
3. **Error Handling** — Tool errors captured and returned to AI for retry
4. **Streaming Support** — Real-time response streaming via Server-Sent Events (SSE)

#### 2. Multi-Agent (MultiAgentEngine)

Advanced multi-agent orchestration (defined in `rio-core`):

**Core Features**:
- **Agent Spawning**: Create multiple agent instances with unique identities
- **Agent-to-Agent (A2A) Communication**: Message routing with @mention syntax
- **Deadlock Prevention**: Call chain tracking prevents circular dependencies
- **Shared Memory**: Evidence Store, Lessons Learned, Decision Log
- **Concurrent Execution**: Tokio-based async/await for parallel agent operations

**Agent Roles** (`rio-identity`):
- `Orchestrator` — Task decomposition, coordination
- `Executor` — Task execution, tool usage
- `Reviewer` — Code review, quality assurance
- `Researcher` — Information gathering, analysis

**@Mention Routing** (`rio-router`):
- `@agent_name` — Route to specific agent
- `@agent1 @agent2` — Route to multiple agents (broadcast)
- `@all` — Broadcast to all active agents

**Shared Memory System** (`rio-memory`):
- **Evidence Store**: Key-value facts with confidence scoring (0.0-1.0)
- **Lessons Store**: CARL model (Context-Action-Result-Lesson) with tags
- **Decision Store**: Decision records with rationale and alternatives
- **SQLite Backend**: Persistent storage with async API (sqlx + tokio)

### AI Provider System

The `AIProvider` trait (`rio-providers`) abstracts all AI services:

```rust
#[async_trait]
pub trait AIProvider: Send + Sync {
    async fn stream_message(&self, messages: &[Message]) -> Result<BoxStream<'static, Result<String>>>;
    fn model_name(&self) -> &str;
}
```

**Supported Providers**:
- **Claude** (Anthropic): Sonnet/Opus/Haiku 3.x/4.x, thinking mode, 200K context
- **OpenAI**: GPT-4.x, o1/o3, vision, JSON mode, up to 1M context
- **Gemini** (Google): 1.5/2.x, vision, JSON mode, 1M context
- **DeepSeek**: v3/r1, thinking mode, 64K context

### Tool System

8 built-in tools implementing the `Tool` trait (`rio-tools`):

| Tool | Risk Level | Confirmation Required |
|------|------------|----------------------|
| `execute_command` | Classified per command | Per `CommandClassifier` |
| `read_file` | safe | No |
| `write_file` | normal | Conditional |
| `edit_file` | normal | Conditional |
| `apply_patch` | normal | Yes |
| `search_files` | safe | No |
| `find_files` | safe | No |
| `list_directory` | safe | No |

### Command Risk Classification (rio-security)

The `CommandClassifier` handles complex parsing including pipes, control operators (`&&`, `||`, `;`), and redirections:

- **safe**: Read-only commands (ls, cat, grep, git status/log/diff) → auto-execute
- **normal**: Most commands → user confirmation
- **dangerous**: rm -rf, sudo, curl, wget, kill -9, sed -i → always confirm

The classifier recursively analyzes compound commands and returns the highest risk level found.

## Development Patterns

### Adding a New Tool

1. Create a struct in `crates/rio-tools/src/` implementing `Tool` trait
2. Implement `name()`, `description()`, `parameters()`, and `execute()`
3. Register in `ToolRegistry::new()`

Example:
```rust
pub struct MyTool;

#[async_trait]
impl Tool for MyTool {
    fn name(&self) -> &str { "my_tool" }
    fn description(&self) -> &str { "Does something useful" }
    fn parameters(&self) -> serde_json::Value { /* JSON schema */ }
    async fn execute(&self, args: serde_json::Value) -> Result<String> {
        // Implementation
    }
}
```

### Adding a New AI Service Provider

1. Create a struct in `crates/rio-providers/src/` implementing `AIProvider` trait
2. Implement `stream_message()` and `model_name()`
3. Add construction logic to provider factory

Example:
```rust
pub struct MyProvider {
    api_key: String,
    model: String,
}

#[async_trait]
impl AIProvider for MyProvider {
    async fn stream_message(&self, messages: &[Message]) -> Result<BoxStream<'static, Result<String>>> {
        // SSE streaming implementation
    }
    
    fn model_name(&self) -> &str {
        &self.model
    }
}
```

### Adding Tests

**Always add tests when modifying critical logic.** Run tests before committing:

```bash
cargo test
cargo clippy -- -D warnings
```

Key test locations:
- `crates/rio-security/src/classifier.rs` — Command classification tests
- `crates/rio-router/src/mention.rs` — @mention parsing tests
- `crates/rio-router/src/router.rs` — A2A routing tests
- `crates/rio-memory/src/*.rs` — Memory store tests (evidence/lessons/decisions)

## File Structure

```
rio-agent/
├── Cargo.toml                          # Workspace manifest
├── Cargo.lock                          # Dependency lock file
├── crates/
│   ├── rio-core/
│   │   ├── src/
│   │   │   ├── lib.rs                  # Core types (Message, Role, ToolCall)
│   │   │   ├── agent.rs                # AgentEngine (single agent)
│   │   │   └── multi_agent.rs          # MultiAgentEngine (orchestration)
│   │   └── Cargo.toml
│   ├── rio-providers/
│   │   ├── src/
│   │   │   ├── lib.rs                  # AIProvider trait
│   │   │   ├── claude.rs               # Claude implementation
│   │   │   ├── openai.rs               # OpenAI implementation
│   │   │   ├── gemini.rs               # Gemini implementation
│   │   │   └── deepseek.rs             # DeepSeek implementation
│   │   └── Cargo.toml
│   ├── rio-tools/
│   │   ├── src/
│   │   │   ├── lib.rs                  # Tool trait + ToolRegistry
│   │   │   ├── execute_command.rs      # Command execution
│   │   │   ├── read_file.rs            # File reading
│   │   │   ├── write_file.rs           # File writing
│   │   │   ├── edit_file.rs            # File editing
│   │   │   └── search_files.rs         # Content search
│   │   └── Cargo.toml
│   ├── rio-storage/
│   │   ├── src/
│   │   │   ├── lib.rs                  # Storage trait
│   │   │   └── sqlite.rs               # SQLite implementation
│   │   └── Cargo.toml
│   ├── rio-security/
│   │   ├── src/
│   │   │   ├── lib.rs                  # Security module exports
│   │   │   ├── classifier.rs           # CommandClassifier
│   │   │   └── path_validator.rs       # Path security
│   │   └── Cargo.toml
│   ├── rio-cli/
│   │   ├── src/
│   │   │   └── main.rs                 # CLI entry point
│   │   └── Cargo.toml
│   ├── rio-identity/
│   │   ├── src/
│   │   │   └── lib.rs                  # AgentIdentity, AgentRole, Capability
│   │   └── Cargo.toml
│   ├── rio-router/
│   │   ├── src/
│   │   │   ├── lib.rs                  # Router exports
│   │   │   ├── mention.rs              # @mention parser
│   │   │   └── router.rs               # A2A message router
│   │   └── Cargo.toml
│   └── rio-memory/
│       ├── src/
│       │   ├── lib.rs                  # SharedMemory manager
│       │   ├── evidence.rs             # Evidence Store
│       │   ├── lessons.rs              # Lessons Store
│       │   └── decisions.rs            # Decision Store
│       └── Cargo.toml
├── docs/
│   ├── SWIFT_TO_RUST_MIGRATION.md      # Migration analysis document
│   └── ...
└── target/                             # Build artifacts (gitignored)
```

## Common Gotchas

1. **Async Runtime**: All async code uses `tokio`. Always use `#[tokio::test]` for async tests.
2. **Streaming Response Parsing**: SSE format uses `data: ` prefix; handle incomplete chunks with buffer accumulation.
3. **Error Handling**: Use `anyhow::Result` for application errors, `thiserror` for library errors.
4. **SQLite Connections**: Always use connection pooling (`SqlitePool`), never raw connections.
5. **Deadlock Prevention**: A2A Router tracks call chains to detect cycles (A→B→A is rejected).
6. **Confidence Clamping**: Evidence confidence is auto-clamped to [0.0, 1.0] range.

## Testing Strategy

Run tests before committing changes to core logic:

```bash
# Run all tests
cargo test

# Run specific crate tests
cargo test -p rio-security
cargo test -p rio-router
cargo test -p rio-memory

# Run with output
cargo test -- --nocapture

# Lint check (zero warnings)
cargo clippy -- -D warnings
```

**Test Coverage Status** (as of 2026-06-21):
- Total: 69 tests
- Status: ✅ All passing
- Clippy warnings: 0

Key test suites:
- `rio-security` — Command risk classification (8 tests)
- `rio-router` — @mention parsing + A2A routing (31 tests)
- `rio-memory` — Evidence/Lessons/Decisions stores (26 tests)
- `rio-identity` — Agent roles and capabilities (4 tests)

## Notes on Dependencies

This project uses minimal, well-vetted dependencies:

- **tokio**: Async runtime (industry standard)
- **reqwest**: HTTP client for AI API calls
- **serde/serde_json**: Serialization (ubiquitous in Rust ecosystem)
- **sqlx**: Async SQLite driver (compile-time verified queries)
- **anyhow/thiserror**: Error handling (standard practice)
- **keyring**: OS-native secure storage (cross-platform)
- **clap**: CLI argument parsing (de facto standard)

All dependencies are from crates.io with high download counts and active maintenance.
