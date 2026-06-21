# Rio Agent - Rust CLI

Cross-platform AI programming assistant built with Rust and Tauri.

## Phase 1: CLI Core (Current)

A command-line interface that supports:
- Basic conversation with AI models
- Tool execution (read_file, write_file, execute_command, list_directory)
- Session persistence with SQLite
- Cross-platform support (macOS, Windows, Linux)

## Prerequisites

- Rust 1.75+
- SQLite 3

## Build

```bash
# Build all crates
cargo build

# Build release version
cargo build --release
```

## Usage

### Environment Setup

Set your Anthropic API key:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

### Basic Commands

```bash
# Start a new chat
cargo run --bin rio-cli chat "List files in current directory"

# Continue a session
cargo run --bin rio-cli chat "Read Cargo.toml" --session <session-id>

# List all sessions
cargo run --bin rio-cli sessions

# Configure a model
cargo run --bin rio-cli config add-model claude --api-key sk-ant-... --model claude-3-5-sonnet-20241022
```

### Interactive Mode

```bash
# Start interactive chat (prompts for input)
cargo run --bin rio-cli chat
```

## Project Structure

```
crates/
├── rio-core/          # Core abstractions (Message, Tool, AIProvider, AgentEngine)
├── rio-providers/     # AI provider implementations (Claude, OpenAI, etc.)
├── rio-tools/         # Tool implementations (file operations, command execution)
├── rio-storage/       # SQLite persistence layer
├── rio-security/      # Command risk classification
└── rio-cli/           # CLI entry point
```

## Testing

```bash
# Run all tests
cargo test --workspace

# Run tests for a specific crate
cargo test -p rio-security
```

## Next Steps (Phase 2-4)

- [ ] Tauri desktop UI
- [ ] Multi-agent DAG execution
- [ ] Task planner and critic service
- [ ] Skills framework
- [ ] Agent persistent identity
- [ ] Shared knowledge base

## License

MIT
