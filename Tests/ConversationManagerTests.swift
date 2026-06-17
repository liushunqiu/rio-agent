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
            workingDirectory: "/tmp/project"
        )

        XCTAssertEqual(manager.currentConversation?.updatedAt, currentUpdatedAt)
        XCTAssertEqual(manager.conversations.map(\.id), [older.id, current.id])
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
}
