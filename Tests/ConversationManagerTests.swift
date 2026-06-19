import XCTest
@testable import RioAgent

@MainActor
final class ConversationManagerTests: XCTestCase {
    func testUpdateCurrentConversationMovesConversationToTop() {
        let manager = ConversationManager()
        manager.conversations = []

        let older = Conversation(
            title: "Older",
            messages: [.user("older")],
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let current = Conversation(
            title: "Current",
            messages: [.user("current")],
            updatedAt: Date(timeIntervalSince1970: 5)
        )

        manager.conversations = [older, current]
        manager.currentConversation = current

        manager.updateCurrentConversation(messages: [.user("updated current")])

        XCTAssertEqual(manager.conversations.first?.id, current.id)
        XCTAssertEqual(manager.currentConversation?.id, current.id)
        XCTAssertEqual(manager.conversations.first?.messages.last?.content, "updated current")
    }

    func testDeletingNonCurrentConversationKeepsCurrentConversationSelected() {
        let manager = ConversationManager()
        manager.conversations = []

        let current = Conversation(
            title: "Current",
            messages: [.user("current")]
        )
        let other = Conversation(
            title: "Other",
            messages: [.user("other")]
        )

        manager.conversations = [current, other]
        manager.currentConversation = current

        manager.deleteConversation(other)

        XCTAssertEqual(manager.currentConversation?.id, current.id)
        XCTAssertEqual(manager.conversations.map(\.id), [current.id])
    }

    func testCreateNewConversationCanCarryWorkingDirectory() {
        let manager = ConversationManager()
        manager.conversations = []

        let conversation = manager.createNewConversation(workingDirectory: "/tmp/project")

        XCTAssertEqual(conversation.workingDirectory, "/tmp/project")
        XCTAssertEqual(manager.currentConversation?.workingDirectory, "/tmp/project")
        XCTAssertEqual(manager.conversations.first?.workingDirectory, "/tmp/project")
    }

    func testSelectConversationUsesStoredConversationSnapshot() {
        let manager = ConversationManager()
        manager.conversations = []

        let id = UUID()
        let stale = Conversation(
            id: id,
            title: "Current",
            messages: [.user("old message")],
            pendingDecision: .chooseExecutionModeForTask("旧任务"),
            draftInput: "old draft",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let stored = Conversation(
            id: id,
            title: "Current",
            messages: [.user("new message")],
            pendingDecision: .chooseExecutionModeForTask("新任务"),
            draftInput: "new draft",
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        manager.conversations = [stored]

        manager.selectConversation(stale)

        XCTAssertEqual(manager.currentConversation?.messages.last?.content, "new message")
        XCTAssertEqual(manager.currentConversation?.draftInput, "new draft")
        XCTAssertEqual(manager.currentConversation?.pendingDecision, .chooseExecutionModeForTask("新任务"))
    }

    func testUpdateCurrentConversationSkipsRedundantUpdates() {
        let manager = ConversationManager()
        manager.conversations = []
        let sameMessage = Message.user("same")

        let older = Conversation(
            title: "Older",
            messages: [.user("older")],
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let currentUpdatedAt = Date(timeIntervalSince1970: 10)
        let current = Conversation(
            title: "Current",
            messages: [sameMessage],
            workingDirectory: "/tmp/project",
            updatedAt: currentUpdatedAt
        )

        manager.conversations = [older, current]
        manager.currentConversation = current

        manager.updateCurrentConversation(
            messages: [sameMessage],
            workingDirectory: .set("/tmp/project")
        )

        XCTAssertEqual(manager.currentConversation?.updatedAt, currentUpdatedAt)
        XCTAssertEqual(manager.conversations.map(\.id), [older.id, current.id])
    }

    func testUpdateCurrentConversationPreservesWorkingDirectoryWhenOmitted() {
        let manager = ConversationManager()
        manager.conversations = []

        let current = Conversation(
            title: "Current",
            messages: [.user("before")],
            workingDirectory: "/tmp/project",
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [current]
        manager.currentConversation = current

        manager.updateCurrentConversation(messages: [.user("after")])

        XCTAssertEqual(manager.currentConversation?.workingDirectory, "/tmp/project")
        XCTAssertEqual(manager.conversations.first?.workingDirectory, "/tmp/project")
    }

    func testUpdateCurrentConversationCanExplicitlyClearWorkingDirectory() {
        let manager = ConversationManager()
        manager.conversations = []

        let current = Conversation(
            title: "Current",
            messages: [.user("before")],
            workingDirectory: "/tmp/project",
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [current]
        manager.currentConversation = current

        manager.updateCurrentConversation(
            messages: [.user("after")],
            workingDirectory: .set(nil)
        )

        XCTAssertNil(manager.currentConversation?.workingDirectory)
        XCTAssertNil(manager.conversations.first?.workingDirectory)
    }

    func testUpdateCurrentConversationPersistsPendingDecision() {
        let manager = ConversationManager()
        manager.conversations = []

        let current = Conversation(
            title: "Current",
            messages: [.user("before")],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [current]
        manager.currentConversation = current

        manager.updateCurrentConversation(
            messages: [.user("after")],
            pendingDecision: .set(.chooseExecutionModeForTask("请继续扫描仓库"))
        )

        XCTAssertEqual(manager.currentConversation?.pendingDecision, .chooseExecutionModeForTask("请继续扫描仓库"))
        XCTAssertEqual(manager.conversations.first?.pendingDecision, .chooseExecutionModeForTask("请继续扫描仓库"))
    }

    func testUpdateCurrentConversationGeneratesTitleWithoutSecondMutation() throws {
        let manager = ConversationManager()
        manager.conversations = []
        let firstMessage = Message.user("这是第一次发送的内容")

        let current = Conversation(
            title: "新对话",
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [current]
        manager.currentConversation = current

        manager.updateCurrentConversation(messages: [firstMessage])
        let firstUpdatedAt = try XCTUnwrap(manager.currentConversation?.updatedAt)
        let firstTitle = manager.currentConversation?.title

        manager.updateCurrentConversation(messages: [firstMessage])

        XCTAssertEqual(manager.currentConversation?.title, firstTitle)
        let secondUpdatedAt = try XCTUnwrap(manager.currentConversation?.updatedAt)
        XCTAssertEqual(
            secondUpdatedAt.timeIntervalSince1970,
            firstUpdatedAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testUpdateDraftInputPersistsToCurrentConversation() {
        let manager = ConversationManager()
        manager.conversations = []

        let updatedAt = Date(timeIntervalSince1970: 50)
        let current = Conversation(
            title: "Draft Test",
            messages: [],
            draftInput: "",
            updatedAt: updatedAt
        )

        manager.conversations = [current]
        manager.currentConversation = current

        manager.updateDraftInput("待发送草稿")

        XCTAssertEqual(manager.currentConversation?.draftInput, "待发送草稿")
        XCTAssertEqual(manager.conversations.first?.draftInput, "待发送草稿")
        XCTAssertEqual(manager.currentConversation?.updatedAt, updatedAt)
        XCTAssertEqual(manager.conversations.first?.updatedAt, updatedAt)
    }

    func testUpdateDraftInputDoesNotReorderConversations() {
        let manager = ConversationManager()
        manager.conversations = []

        let older = Conversation(
            title: "Older",
            messages: [.user("older")],
            draftInput: "",
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let current = Conversation(
            title: "Current",
            messages: [.user("current")],
            draftInput: "",
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [older, current]
        manager.currentConversation = current

        manager.updateDraftInput("new draft")

        XCTAssertEqual(manager.conversations.map(\.id), [older.id, current.id])
    }

    func testUpdateDraftInputCanRestoreLatestUserTaskWithoutReorderingConversation() {
        let manager = ConversationManager()
        manager.conversations = []

        let older = Conversation(
            title: "Older",
            messages: [.user("older task")],
            draftInput: "",
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let current = Conversation(
            title: "Current",
            messages: [
                .user("请继续修复刚才失败的任务"),
                .assistant("执行时遇到错误")
            ],
            draftInput: "",
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [older, current]
        manager.currentConversation = current

        manager.updateDraftInput("请继续修复刚才失败的任务")

        XCTAssertEqual(manager.currentConversation?.draftInput, "请继续修复刚才失败的任务")
        XCTAssertEqual(manager.conversations.map(\.id), [older.id, current.id])
        XCTAssertEqual(manager.currentConversation?.updatedAt, current.updatedAt)
    }

    func testUpdateWorkingDirectoryPersistsWithoutReorderingOrTouchingUpdatedAt() {
        let manager = ConversationManager()
        manager.conversations = []

        let older = Conversation(
            title: "Older",
            messages: [.user("older task")],
            workingDirectory: "/tmp/older",
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        let current = Conversation(
            title: "Current",
            messages: [],
            workingDirectory: nil,
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [older, current]
        manager.currentConversation = current

        manager.updateWorkingDirectory("/tmp/current")

        XCTAssertEqual(manager.currentConversation?.workingDirectory, "/tmp/current")
        XCTAssertEqual(manager.conversations.map(\.id), [older.id, current.id])
        XCTAssertEqual(manager.currentConversation?.updatedAt, current.updatedAt)
    }

    func testConversationPreviewPrefersUserOrAssistantContentOverTrailingSystemPrompt() {
        let conversation = Conversation(
            title: "Preview",
            messages: [
                .user("请分析这个项目"),
                .assistant("已经完成第一轮扫描"),
                .system(
                    "已切换为单 Agent 模式。",
                    source: MessageSource(agentName: "Planning")
                )
            ]
        )

        XCTAssertEqual(conversation.latestPreviewContent, "已经完成第一轮扫描")
        XCTAssertEqual(conversation.visibleMessageCount, 3)
    }

    func testConversationPreviewPrefersUnsentDraftOverOlderMessages() {
        let conversation = Conversation(
            title: "Draft Preview",
            messages: [
                .user("旧任务"),
                .assistant("旧回复")
            ],
            draftInput: "继续优化侧栏\n草稿体验"
        )

        XCTAssertEqual(conversation.latestPreviewContent, "继续优化侧栏 草稿体验")
        XCTAssertEqual(conversation.visibleMessageCount, 2)
    }

    func testConversationPreviewUsesPendingDecisionWhenNoDraftExists() {
        let conversation = Conversation(
            title: "Pending Preview",
            messages: [
                .user("请分析这个项目并修改多个文件后再测试")
            ],
            pendingDecision: .chooseExecutionModeForTask("请分析这个项目并修改多个文件后再测试")
        )

        XCTAssertEqual(
            conversation.latestPreviewContent,
            "请分析这个项目并修改多个文件后再测试"
        )
    }

    func testInternalOnlyMessagesDoNotCreateVisibleTranscript() {
        let conversation = Conversation(
            title: "Internal",
            messages: [
                Message.system(
                    "[Internal Planning Context]",
                    presentation: .internalOnly
                )
            ]
        )

        XCTAssertEqual(conversation.visibleMessageCount, 0)
        XCTAssertFalse(conversation.hasVisibleTranscript)
        XCTAssertNil(conversation.latestPreviewContent)
    }

    func testUpdateCurrentConversationTitleSkipsConfirmationReplyAndUsesFirstRealTask() {
        let manager = ConversationManager()
        manager.conversations = []

        let current = Conversation(
            title: "新对话",
            messages: [],
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        manager.conversations = [current]
        manager.currentConversation = current

        manager.updateCurrentConversation(messages: [
            .user("是"),
            .system("已确认使用 Multi-Agent 模式。"),
            .user("请继续扫描仓库并修复交互状态问题")
        ])

        XCTAssertEqual(manager.currentConversation?.title, "请继续扫描仓库并修复交互状态问题")
    }

    func testGeneratedTitleSkipsSlashCommandAndNormalizesLineBreaks() {
        let conversation = Conversation(
            messages: [
                .user("/help"),
                .user("继续优化首页\n和会话交互")
            ]
        )

        XCTAssertEqual(conversation.generatedTitle, "继续优化首页 和会话交互")
    }

    func testConversationDecodingBackfillsMissingDraftInput() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Legacy",
          "messages": [],
          "workingDirectory": "/tmp/project",
          "createdAt": 0,
          "updatedAt": 1
        }
        """.data(using: .utf8)!

        let conversation = try JSONDecoder().decode(Conversation.self, from: json)

        XCTAssertEqual(conversation.draftInput, "")
        XCTAssertNil(conversation.pendingDecision)
    }

    func testConversationEqualityDetectsMessageContentChanges() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)

        let original = Conversation(
            id: id,
            title: "Same",
            messages: [.user("before")],
            workingDirectory: "/tmp/project",
            draftInput: "draft",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let changed = Conversation(
            id: id,
            title: "Same",
            messages: [.user("after")],
            workingDirectory: "/tmp/project",
            draftInput: "draft",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertNotEqual(original, changed)
    }

    func testConversationEqualityDetectsDraftAndWorkingDirectoryChanges() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)

        let original = Conversation(
            id: id,
            title: "Same",
            messages: [.user("message")],
            workingDirectory: "/tmp/project-a",
            draftInput: "draft-a",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let changed = Conversation(
            id: id,
            title: "Same",
            messages: [.user("message")],
            workingDirectory: "/tmp/project-b",
            draftInput: "draft-b",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertNotEqual(original, changed)
    }

    func testConversationEqualityDetectsToolMetadataChanges() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let updatedAt = Date(timeIntervalSince1970: 200)

        let baseMessage = Message(
            id: UUID(),
            role: .assistant,
            content: "正在处理",
            toolCalls: [ToolCall(id: "call-1", name: "read_file")]
        )
        var changedMessage = baseMessage
        changedMessage.toolResults = [ToolResult.success(toolCallId: "call-1", output: "README content")]

        let original = Conversation(
            id: id,
            title: "Same",
            messages: [baseMessage],
            workingDirectory: "/tmp/project-a",
            draftInput: "draft-a",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let changed = Conversation(
            id: id,
            title: "Same",
            messages: [changedMessage],
            workingDirectory: "/tmp/project-a",
            draftInput: "draft-a",
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        XCTAssertNotEqual(original, changed)
    }
}
