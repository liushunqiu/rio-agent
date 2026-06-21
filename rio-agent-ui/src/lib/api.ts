import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type { ConversationInfo, MessageInfo, MessageChunk } from './types';

// 对话管理
export async function createConversation(): Promise<string> {
  return await invoke('create_conversation');
}

export async function listConversations(): Promise<ConversationInfo[]> {
  return await invoke('list_conversations');
}

export async function deleteConversation(conversationId: string): Promise<void> {
  await invoke('delete_conversation', { conversationId });
}

export async function getConversationMessages(conversationId: string): Promise<MessageInfo[]> {
  return await invoke('get_conversation_messages', { conversationId });
}

export async function sendMessage(
  conversationId: string,
  content: string,
  onChunk: (chunk: string) => void,
  onError?: (error: string) => void
): Promise<void> {
  // 监听流式消息块
  const unlisten = await listen<MessageChunk>('message_chunk', (event) => {
    if (event.payload.conversation_id === conversationId) {
      onChunk(event.payload.content);
    }
  });

  // 监听错误
  const unlistenError = await listen<string>('message_error', (event) => {
    if (onError) {
      onError(event.payload);
    }
  });

  try {
    await invoke('send_message', { conversationId, content });
  } finally {
    unlisten();
    unlistenError();
  }
}
