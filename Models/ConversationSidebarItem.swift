import Foundation

struct ConversationSidebarItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let workingDirectory: String?
    let workingDirectoryLabel: String
    let hasDraft: Bool

    init(conversation: Conversation) {
        id = conversation.id
        title = conversation.title
        workingDirectory = conversation.workingDirectory
        let trimmedWorkingDirectory = conversation.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedWorkingDirectory, !trimmedWorkingDirectory.isEmpty {
            workingDirectoryLabel = trimmedWorkingDirectory
        } else {
            workingDirectoryLabel = "未设置工作目录"
        }

        let trimmedDraft = conversation.draftInput.trimmingCharacters(in: .whitespacesAndNewlines)
        hasDraft = !trimmedDraft.isEmpty
    }
}
