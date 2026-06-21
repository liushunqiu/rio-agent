use anyhow::Result;
use clap::{Parser, Subcommand};
use rio_core::{AgentEngine, Message, ToolRegistry};
use rio_providers::ClaudeProvider;
use rio_storage::Storage;
use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::Arc;
use tracing::info;

#[derive(Parser)]
#[command(name = "rio-cli")]
#[command(about = "Rio Agent CLI - Cross-platform AI programming assistant", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Start a chat session
    Chat {
        /// The message to send
        message: Option<String>,

        /// Session ID to continue
        #[arg(short, long)]
        session: Option<String>,
    },
    /// List all sessions
    Sessions,
    /// Configure API keys and models
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },
}

#[derive(Subcommand)]
enum ConfigAction {
    /// Add a new model configuration
    AddModel {
        /// Provider name (claude, openai, etc.)
        provider: String,

        /// API key
        #[arg(long)]
        api_key: String,

        /// Model name
        #[arg(long, default_value = "claude-3-5-sonnet-20241022")]
        model: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info"))
        )
        .init();

    let cli = Cli::parse();

    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let data_dir = PathBuf::from(&home).join(".rio-agent");
    std::fs::create_dir_all(&data_dir)?;

    let db_path = data_dir.join("rio-agent.db");
    let storage = Storage::new(&format!("sqlite:{}", db_path.display())).await?;

    match cli.command {
        Commands::Chat { message, session } => {
            handle_chat(storage, message, session).await?;
        }
        Commands::Sessions => {
            handle_sessions(storage).await?;
        }
        Commands::Config { action } => {
            handle_config(action, &data_dir).await?;
        }
    }

    Ok(())
}

async fn handle_chat(storage: Storage, message: Option<String>, session_id: Option<String>) -> Result<()> {
    let api_key = std::env::var("ANTHROPIC_API_KEY")
        .expect("ANTHROPIC_API_KEY environment variable not set");

    let provider = Arc::new(ClaudeProvider::new(
        api_key,
        "claude-3-5-sonnet-20241022".to_string(),
    ));

    let mut registry = ToolRegistry::new();
    rio_tools::register_default_tools(&mut registry);
    let tools = Arc::new(registry);

    let engine = AgentEngine::new(provider, tools);

    let session = if let Some(sid) = session_id {
        storage.get_session(&sid).await?
            .ok_or_else(|| anyhow::anyhow!("Session not found: {}", sid))?
    } else {
        storage.create_session("New Chat").await?
    };

    info!("Session: {} ({})", session.title, session.id);

    let mut messages = storage.get_messages(&session.id).await?;

    let user_message = if let Some(msg) = message {
        msg
    } else {
        print!("You: ");
        io::stdout().flush()?;
        let mut input = String::new();
        io::stdin().read_line(&mut input)?;
        input.trim().to_string()
    };

    messages.push(Message::new_user(&user_message));
    storage.save_message(&session.id, &messages[messages.len() - 1]).await?;

    println!("\nAssistant: ");

    let response = engine.run(&mut messages).await?;

    println!("{}", response.content);

    storage.save_message(&session.id, &response).await?;

    println!("\n[Session saved: {}]", session.id);

    Ok(())
}

async fn handle_sessions(storage: Storage) -> Result<()> {
    let sessions = storage.list_sessions().await?;

    if sessions.is_empty() {
        println!("No sessions found.");
        return Ok(());
    }

    println!("Sessions:");
    for session in sessions {
        println!("  {} - {} ({})", session.id, session.title, session.updated_at.format("%Y-%m-%d %H:%M"));
    }

    Ok(())
}

async fn handle_config(action: ConfigAction, data_dir: &PathBuf) -> Result<()> {
    match action {
        ConfigAction::AddModel { provider, api_key, model } => {
            let config_file = data_dir.join("config.json");

            let mut config: serde_json::Value = if config_file.exists() {
                let content = std::fs::read_to_string(&config_file)?;
                serde_json::from_str(&content)?
            } else {
                serde_json::json!({
                    "models": []
                })
            };

            if let Some(models) = config.get_mut("models").and_then(|v| v.as_array_mut()) {
                models.push(serde_json::json!({
                    "provider": provider,
                    "model": model,
                    "api_key": api_key,
                }));
            }

            std::fs::write(&config_file, serde_json::to_string_pretty(&config)?)?;
            println!("Model configuration added successfully!");
        }
    }

    Ok(())
}
