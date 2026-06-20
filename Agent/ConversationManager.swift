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

    @Published var conversations: [Conversation] = [] {
        didSet {
            syncSidebarItemsAfterConversationMutation()
            publishSidebarState()
        }
    }
    @Published var currentConversation: Conversation? {
        didSet {
            sidebarState.updateSelectedConversationID(currentConversation?.id)
        }
    }
    private(set) var sidebarItems: [ConversationSidebarItem] = []
    let sidebarState = SidebarState()

    private let userDefaults: UserDefaults
    private let saveKey: String
    private var saveDebounceTask: Task<Void, Never>?
    private var pendingSidebarMutation: SidebarMutation?

    /// 对话持久化后端。默认走文件存储（避免 5MB+ 的对话 blob 拖慢 UserDefaults 首访与启动），
    /// 注入非标准 UserDefaults 时（测试/隔离环境）仍走 UserDefaults 以保持往返可测。
    private enum PersistenceStore {
        case userDefaults(UserDefaults)
        case file(URL)
    }

    private let store: PersistenceStore
    private let storeKey: String
    @Published private(set) var isLoadingConversations = false
    private var didCompleteInitialLoad = false
    private var loadCompletionHandlers: [() -> Void] = []

    init(
        userDefaults: UserDefaults = .standard,
        saveKey: String = "saved_conversations"
    ) {
        self.userDefaults = userDefaults
        self.saveKey = saveKey
        self.storeKey = saveKey
        // 标准默认值意味着真实应用环境：使用 Application Support 下的文件存储，
        // 并把历史保存在 UserDefaults 里的旧数据一次性迁移到文件并清除，避免 plist 膨胀。
        if userDefaults == .standard {
            self.store = .file(Self.defaultConversationsFileURL())
            Self.migrateLegacyUserDefaultsIfNeeded(userDefaults: userDefaults, key: saveKey, fileURL: Self.defaultConversationsFileURL())
            loadConversationsAsync()
        } else {
            self.store = .userDefaults(userDefaults)
            loadConversations()
        }
    }

    private static func defaultConversationsFileURL() -> URL {
        let baseURL: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            baseURL = appSupport.appendingPathComponent("RioAgent", isDirectory: true)
        } else {
            baseURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".rio-agent", isDirectory: true)
        }
        let dir = baseURL.appendingPathComponent("Conversations", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("saved_conversations.json")
    }

    /// 一次性迁移：把历史 UserDefaults 里的对话 blob 搬到文件并从 UserDefaults 清除，
    /// 否则 5MB+ 的 plist 会持续拖慢 UserDefaults 首次访问与每次持久化。
    private static func migrateLegacyUserDefaultsIfNeeded(userDefaults: UserDefaults, key: String, fileURL: URL) {
        guard let data = userDefaults.data(forKey: key) else { return }
        // 文件已存在则视为已迁移过，仅清理 UserDefaults 残留。
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try data.write(to: fileURL, options: .atomic)
            } catch {
                RioLogger.config.error("迁移历史对话到文件失败: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        userDefaults.removeObject(forKey: key)
        RioLogger.config.info("📦 已将历史对话迁移到文件存储并清理 UserDefaults")
    }

    /// 启动加载完成后的回调（仅触发一次），用于在首屏渲染后再把当前对话灌入引擎。
    func performAfterInitialLoad(_ action: @escaping () -> Void) {
        if didCompleteInitialLoad {
            action()
        } else {
            loadCompletionHandlers.append(action)
        }
    }

    private func signalInitialLoadComplete() {
        guard !didCompleteInitialLoad else { return }
        didCompleteInitialLoad = true
        let handlers = loadCompletionHandlers
        loadCompletionHandlers.removeAll()
        for handler in handlers { handler() }
    }

    // MARK: - Public Methods

    func createNewConversation(workingDirectory: String? = nil) -> Conversation {
        let conversation = Conversation(workingDirectory: workingDirectory)
        pendingSidebarMutation = .insert(ConversationSidebarItem(conversation: conversation), at: 0)
        conversations.insert(conversation, at: 0)
        currentConversation = conversation
        debouncedSave()
        return conversation
    }

    @discardableResult
    func selectConversation(_ conversation: Conversation) -> Conversation? {
        guard let storedConversation = conversations.first(where: { $0.id == conversation.id }) else {
            return nil
        }

        currentConversation = storedConversation
        return storedConversation
    }

    func conversation(withID id: UUID) -> Conversation? {
        conversations.first { $0.id == id }
    }

    @discardableResult
    func deleteConversation(_ conversation: Conversation) -> Conversation? {
        pendingSidebarMutation = .remove(id: conversation.id)
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first
        }
        flushPendingSave()
        return currentConversation
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
            let item = ConversationSidebarItem(conversation: current)
            if index == 0 {
                pendingSidebarMutation = .replace(item)
                conversations[0] = current
            } else {
                var updatedConversations = conversations
                updatedConversations.remove(at: index)
                updatedConversations.insert(current, at: 0)
                pendingSidebarMutation = .moveToTop(item)
                conversations = updatedConversations
            }
        } else {
            // 如果找不到，可能是新对话，插入到数组开头
            pendingSidebarMutation = .insert(ConversationSidebarItem(conversation: current), at: 0)
            conversations = [current] + conversations
        }

        debouncedSave()
    }

    func updateDraftInput(_ draftInput: String) {
        guard var current = currentConversation else { return }
        guard current.draftInput != draftInput else { return }

        current.draftInput = draftInput
        currentConversation = current

        if let index = conversations.firstIndex(where: { $0.id == current.id }) {
            pendingSidebarMutation = .replace(ConversationSidebarItem(conversation: current))
            conversations[index] = current
        } else {
            pendingSidebarMutation = .insert(ConversationSidebarItem(conversation: current), at: 0)
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
            pendingSidebarMutation = .replace(ConversationSidebarItem(conversation: current))
            conversations[index] = current
        } else {
            pendingSidebarMutation = .insert(ConversationSidebarItem(conversation: current), at: 0)
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
            switch store {
            case .userDefaults:
                userDefaults.set(data, forKey: saveKey)
            case .file(let url):
                try data.write(to: url, options: .atomic)
            }
        } catch {
            RioLogger.config.error("保存对话失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadConversations() {
        guard let data = userDefaults.data(forKey: saveKey) else { return }
        applyLoadedConversations(data)
        signalInitialLoadComplete()
    }

    /// 后台异步加载对话，避免启动时在主线程同步解码数 MB 的历史 blob 造成卡顿。
    private func loadConversationsAsync() {
        isLoadingConversations = true
        let store = self.store
        Task.detached(priority: .userInitiated) { [weak self] in
            let data: Data?
            switch store {
            case .userDefaults(let defaults):
                data = defaults.data(forKey: "saved_conversations")
            case .file(let url):
                data = try? Data(contentsOf: url)
            }
            let manager = self
            await MainActor.run { manager?.finishAsyncLoad(with: data) }
        }
    }

    private func finishAsyncLoad(with data: Data?) {
        isLoadingConversations = false
        applyLoadedConversations(data)
        signalInitialLoadComplete()
    }

    private func applyLoadedConversations(_ data: Data?) {
        guard let data, !data.isEmpty else {
            signalInitialLoadComplete()
            return
        }
        do {
            let decodedConversations = try JSONDecoder().decode([Conversation].self, from: data)
            conversations = decodedConversations.sorted { $0.updatedAt > $1.updatedAt }
            currentConversation = conversations.first
            rebuildSidebarItems()
            publishSidebarState()
        } catch {
            RioLogger.config.error("加载对话失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publishSidebarState() {
        sidebarState.update(
            items: sidebarItems,
            selectedConversationID: currentConversation?.id
        )
    }

    private func syncSidebarItemsAfterConversationMutation() {
        defer { pendingSidebarMutation = nil }

        guard let pendingSidebarMutation else {
            rebuildSidebarItems()
            return
        }

        switch pendingSidebarMutation {
        case let .insert(item, index):
            guard conversations.indices.contains(index),
                  conversations[index].id == item.id,
                  !sidebarItems.contains(where: { $0.id == item.id }) else {
                rebuildSidebarItems()
                return
            }
            sidebarItems.insert(item, at: min(index, sidebarItems.count))
        case let .remove(id):
            sidebarItems.removeAll { $0.id == id }
            guard sidebarItems.count == conversations.count else {
                rebuildSidebarItems()
                return
            }
        case let .replace(item):
            guard let index = sidebarItems.firstIndex(where: { $0.id == item.id }),
                  conversations.contains(where: { $0.id == item.id }) else {
                rebuildSidebarItems()
                return
            }
            sidebarItems[index] = item
        case let .moveToTop(item):
            guard let index = sidebarItems.firstIndex(where: { $0.id == item.id }),
                  conversations.first?.id == item.id else {
                rebuildSidebarItems()
                return
            }
            sidebarItems.remove(at: index)
            sidebarItems.insert(item, at: 0)
        }
    }

    private func rebuildSidebarItems() {
        sidebarItems = conversations.map { ConversationSidebarItem(conversation: $0) }
    }

    private enum SidebarMutation {
        case insert(ConversationSidebarItem, at: Int)
        case remove(id: UUID)
        case replace(ConversationSidebarItem)
        case moveToTop(ConversationSidebarItem)
    }
}

@MainActor
final class SidebarState: ObservableObject {
    @Published private(set) var items: [ConversationSidebarItem] = []
    @Published private(set) var selectedConversationID: UUID?

    func update(items: [ConversationSidebarItem], selectedConversationID: UUID?) {
        if self.items != items {
            self.items = items
        }
        updateSelectedConversationID(selectedConversationID)
    }

    func updateSelectedConversationID(_ selectedConversationID: UUID?) {
        guard self.selectedConversationID != selectedConversationID else { return }
        self.selectedConversationID = selectedConversationID
    }
}
