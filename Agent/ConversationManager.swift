import Foundation
import os

@MainActor
class ConversationManager: ObservableObject {
    enum WorkingDirectoryUpdate: Equatable {
        case preserve
        case set(String?)
    }

    enum PendingDecisionUpdate: Equatable {
        case preserve
        case set(ConversationPendingDecision?)
    }

    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?

    private let saveKey = "saved_conversations"
    private var saveDebounceTask: Task<Void, Never>?

    init() {
        loadConversations()
    }

    // MARK: - Public Methods

    func createNewConversation(workingDirectory: String? = nil) -> Conversation {
        let conversation = Conversation(workingDirectory: workingDirectory)
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        debouncedSave()
        return conversation
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversations.first(where: { $0.id == conversation.id }) ?? conversation
    }

    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
        debouncedSave()
    }

    func updateCurrentConversation(
        messages: [Message],
        workingDirectory: WorkingDirectoryUpdate = .preserve,
        pendingDecision: PendingDecisionUpdate = .preserve
    ) {
        guard var current = currentConversation else { return }
        let previous = current
        current.messages = messages
        if case let .set(workingDirectory) = workingDirectory {
            current.workingDirectory = workingDirectory
        }
        if case let .set(pendingDecision) = pendingDecision {
            current.pendingDecision = pendingDecision
        }

        if current.title == "新对话" {
            current.title = Conversation(messages: messages).generatedTitle ?? current.title
        }

        guard current.messages != previous.messages
            || current.workingDirectory != previous.workingDirectory
            || current.pendingDecision != previous.pendingDecision
            || current.title != previous.title else {
            return
        }

        current.updatedAt = Date()

        if current.title != previous.title {
            RioLogger.config.info("🏷️ 标题已更新: \(current.title)")
        }

        // 同步更新 currentConversation，确保 @Published 属性正确触发 UI 刷新
        currentConversation = current
        
        // 更新 conversations 数组中对应的元素，并将最近活跃会话移到顶部
        if let index = conversations.firstIndex(where: { $0.id == current.id }) {
            conversations.remove(at: index)
            conversations.insert(current, at: 0)
        } else {
            // 如果找不到，可能是新对话，插入到数组开头
            conversations.insert(current, at: 0)
        }
        
        debouncedSave()
    }

    func updateDraftInput(_ draftInput: String) {
        guard var current = currentConversation else { return }
        guard current.draftInput != draftInput else { return }

        current.draftInput = draftInput
        currentConversation = current

        if let index = conversations.firstIndex(where: { $0.id == current.id }) {
            conversations[index] = current
        } else {
            conversations.insert(current, at: 0)
        }

        debouncedSave()
    }

    func updateWorkingDirectory(_ workingDirectory: String?) {
        guard var current = currentConversation else { return }
        guard current.workingDirectory != workingDirectory else { return }

        current.workingDirectory = workingDirectory
        currentConversation = current

        if let index = conversations.firstIndex(where: { $0.id == current.id }) {
            conversations[index] = current
        } else {
            conversations.insert(current, at: 0)
        }

        debouncedSave()
    }

    func flushPendingSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        saveConversations()
    }

    // MARK: - Persistence

    /// 防抖保存, 避免流式输出期间频繁写入
    private func debouncedSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            self?.saveConversations()
        }
    }

    private func saveConversations() {
        do {
            let data = try JSONEncoder().encode(conversations)
            UserDefaults.standard.set(data, forKey: saveKey)
        } catch {
            RioLogger.config.error("保存对话失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: saveKey) else { return }
        do {
            conversations = try JSONDecoder().decode([Conversation].self, from: data)
            conversations.sort { $0.updatedAt > $1.updatedAt }
            currentConversation = conversations.first
        } catch {
            RioLogger.config.error("加载对话失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}
