// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::Manager;

mod commands;
mod state;

use commands::*;
use state::AppState;

#[tokio::main]
async fn main() {
    // 初始化应用状态
    let app_state = AppState::new()
        .await
        .expect("Failed to initialize app state");

    tauri::Builder::default()
        .manage(app_state)
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            // Conversation commands
            send_message,
            list_conversations,
            create_conversation,
            delete_conversation,
            get_conversation_messages,
            update_conversation_title,

            // Config commands
            list_configurations,
            create_configuration,
            get_active_configuration,
            set_active_configuration,
            delete_configuration,

            // Tool commands
            list_tools,
            execute_tool,
        ])
        .setup(|app| {
            #[cfg(debug_assertions)]
            {
                let window = app.get_webview_window("main").unwrap();
                window.open_devtools();
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
