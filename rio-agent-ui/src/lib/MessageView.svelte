<script lang="ts">
  import { onMount } from 'svelte';
  import type { MessageInfo } from '../types';
  import { getConversationMessages, sendMessage } from './api';

  let { conversationId }: { conversationId: string } = $props();

  let messages = $state<MessageInfo[]>([]);
  let input = $state('');
  let loading = $state(false);
  let streaming = $state(false);
  let streamingContent = $state('');
  let messagesContainer: HTMLDivElement;

  $effect(() => {
    if (conversationId) {
      loadMessages();
    }
  });

  async function loadMessages() {
    try {
      messages = await getConversationMessages(conversationId);
      scrollToBottom();
    } catch (error) {
      console.error('Failed to load messages:', error);
    }
  }

  async function handleSend() {
    if (!input.trim() || loading) return;

    const userMessage = input.trim();
    input = '';
    loading = true;
    streaming = true;
    streamingContent = '';

    // 立即显示用户消息
    messages = [
      ...messages,
      {
        id: Date.now().toString(),
        role: 'user',
        content: userMessage,
        timestamp: new Date().toISOString(),
      },
    ];

    scrollToBottom();

    try {
      await sendMessage(
        conversationId,
        userMessage,
        (chunk) => {
          streamingContent += chunk;
          scrollToBottom();
        },
        (error) => {
          console.error('Streaming error:', error);
        }
      );

      // 流式完成后，添加完整的助手消息
      messages = [
        ...messages,
        {
          id: Date.now().toString(),
          role: 'assistant',
          content: streamingContent,
          timestamp: new Date().toISOString(),
        },
      ];
      streamingContent = '';
    } catch (error) {
      console.error('Failed to send message:', error);
    } finally {
      loading = false;
      streaming = false;
    }
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  }

  function scrollToBottom() {
    setTimeout(() => {
      if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
      }
    }, 0);
  }
</script>

<div class="message-view">
  <div class="messages" bind:this={messagesContainer}>
    {#if messages.length === 0}
      <div class="empty">
        <h3>Start a conversation</h3>
        <p>Send a message to begin chatting with Rio Agent</p>
      </div>
    {:else}
      {#each messages as message (message.id)}
        <div class="message" class:user={message.role === 'user'} class:assistant={message.role === 'assistant'}>
          <div class="role">{message.role === 'user' ? 'You' : 'Rio Agent'}</div>
          <div class="content">{message.content}</div>
          <div class="timestamp">{new Date(message.timestamp).toLocaleTimeString()}</div>
        </div>
      {/each}

      {#if streaming}
        <div class="message assistant streaming">
          <div class="role">Rio Agent</div>
          <div class="content">{streamingContent}<span class="cursor">▊</span></div>
        </div>
      {/if}
    {/if}
  </div>

  <div class="input-area">
    <textarea
      bind:value={input}
      onkeydown={handleKeydown}
      placeholder="Type your message... (Enter to send, Shift+Enter for new line)"
      disabled={loading}
      rows="3"
    ></textarea>
    <button onclick={handleSend} disabled={loading || !input.trim()} class="btn-send">
      {loading ? 'Sending...' : 'Send'}
    </button>
  </div>
</div>

<style>
  .message-view {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: white;
  }

  .messages {
    flex: 1;
    overflow-y: auto;
    padding: 1.5rem;
  }

  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: #6B7077;
    text-align: center;
  }

  .empty h3 {
    margin: 0 0 0.5rem;
    font-size: 1.5rem;
    color: #1E2227;
  }

  .empty p {
    margin: 0;
  }

  .message {
    margin-bottom: 1.5rem;
    padding: 1rem;
    border-radius: 8px;
    max-width: 80%;
  }

  .message.user {
    background: #F7F5F1;
    margin-left: auto;
  }

  .message.assistant {
    background: white;
    border: 1px solid #E7E3DA;
  }

  .role {
    font-size: 0.875rem;
    font-weight: 600;
    color: #3C5A78;
    margin-bottom: 0.5rem;
  }

  .content {
    color: #1E2227;
    line-height: 1.6;
    white-space: pre-wrap;
    word-wrap: break-word;
  }

  .streaming .content {
    position: relative;
  }

  .cursor {
    display: inline-block;
    animation: blink 1s infinite;
    color: #3C5A78;
  }

  @keyframes blink {
    0%, 49% { opacity: 1; }
    50%, 100% { opacity: 0; }
  }

  .timestamp {
    font-size: 0.75rem;
    color: #6B7077;
    margin-top: 0.5rem;
  }

  .input-area {
    display: flex;
    gap: 1rem;
    padding: 1rem;
    border-top: 1px solid #E7E3DA;
    background: #F7F5F1;
  }

  textarea {
    flex: 1;
    padding: 0.75rem;
    border: 1px solid #E7E3DA;
    border-radius: 6px;
    font-family: inherit;
    font-size: 1rem;
    resize: none;
    background: white;
  }

  textarea:focus {
    outline: none;
    border-color: #3C5A78;
  }

  textarea:disabled {
    background: #F7F5F1;
    cursor: not-allowed;
  }

  .btn-send {
    padding: 0.75rem 2rem;
    background: #3C5A78;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 1rem;
    font-weight: 500;
    transition: background 0.2s;
    align-self: flex-end;
  }

  .btn-send:hover:not(:disabled) {
    background: #2E4760;
  }

  .btn-send:disabled {
    background: #6B7077;
    cursor: not-allowed;
  }
</style>
