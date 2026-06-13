import SwiftUI

@main
struct RioAgentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appState.setup()
                    // 窗口初次打开：填满屏幕可见区域（非全屏模式）
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        guard let window = NSApplication.shared.windows.first,
                              let screen = NSScreen.main else { return }
                        window.setFrame(
                            screen.visibleFrame,
                            display: true,
                            animate: false
                        )
                    }
                }
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建对话") {
                    appState.createNewConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var configuration = AIConfiguration()
    @Published var showingSettings = false

    private let configurationKey = "ai_configuration"

    func setup() {
        loadConfiguration()
    }

    func createNewConversation() {
        NotificationCenter.default.post(name: .createNewConversation, object: nil)
    }

    func showSettings() {
        showingSettings = true
    }

    // MARK: - Configuration Persistence

    func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: configurationKey) else { return }
        do {
            configuration = try JSONDecoder().decode(AIConfiguration.self, from: data)
        } catch {
            print("Failed to load configuration: \(error)")
        }
    }

    func saveConfiguration() {
        do {
            let data = try JSONEncoder().encode(configuration)
            UserDefaults.standard.set(data, forKey: configurationKey)
        } catch {
            print("Failed to save configuration: \(error)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let createNewConversation = Notification.Name("createNewConversation")
}
