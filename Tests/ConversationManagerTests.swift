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
}
