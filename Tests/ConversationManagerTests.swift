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

    func testUpdateDraftInputPersistsToCurrentConversation() {
        let manager = ConversationManager()
        manager.conversations = []

        let current = Conversation(
            title: "Draft Test",
            messages: [],
            draftInput: ""
        )

        manager.conversations = [current]
        manager.currentConversation = current

        manager.updateDraftInput("待发送草稿")

        XCTAssertEqual(manager.currentConversation?.draftInput, "待发送草稿")
        XCTAssertEqual(manager.conversations.first?.draftInput, "待发送草稿")
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
}
