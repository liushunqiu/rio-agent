use rio_core::{Message, Role};

#[test]
fn test_message_creation() {
    let user_msg = Message::new_user("Hello");
    assert_eq!(user_msg.role, Role::User);
    assert_eq!(user_msg.content, "Hello");
    assert!(user_msg.tool_calls.is_none());

    let assistant_msg = Message::new_assistant("Hi there");
    assert_eq!(assistant_msg.role, Role::Assistant);
    assert_eq!(assistant_msg.content, "Hi there");
}

#[test]
fn test_tool_result_message() {
    let tool_result = Message::new_tool_result("call_123".to_string(), "file contents");
    assert_eq!(tool_result.role, Role::User);
    assert_eq!(tool_result.content, "file contents");
    assert_eq!(tool_result.tool_call_id, Some("call_123".to_string()));
}
