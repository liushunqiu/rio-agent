import SwiftUI

@main
struct RioAgentApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .ignoresSafeArea(.container, edges: .top)
                .onAppear {
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
                    NotificationCenter.default.post(name: .createNewConversation, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let createNewConversation = Notification.Name("createNewConversation")
}
