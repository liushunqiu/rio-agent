// Tauri Command 返回类型

export interface ConversationInfo {
  id: string;
  title: string;
  created_at: string;
  updated_at: string;
}

export interface MessageInfo {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: string;
}

export interface MessageChunk {
  conversation_id: string;
  content: string;
}

export interface ToolInfo {
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

export interface ConfigInfo {
  id: string;
  name: string;
  provider: string;
  model: string;
  is_active: boolean;
}
