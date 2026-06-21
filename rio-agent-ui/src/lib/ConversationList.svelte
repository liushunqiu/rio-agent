<script lang="ts">
  import { onMount } from 'svelte';
  import type { ConversationInfo } from '../types';
  import { listConversations, createConversation, deleteConversation } from './api';

  let conversations = $state<ConversationInfo[]>([]);
  let selectedId = $state<string | null>(null);
  let loading = $state(false);

  let { onSelect = () => {} }: { onSelect?: (id: string) => void } = $props();

  onMount(async () => {
    await loadConversations();
  });

  async function loadConversations() {
    loading = true;
    try {
      conversations = await listConversations();
    } catch (error) {
      console.error('Failed to load conversations:', error);
    } finally {
      loading = false;
    }
  }

  async function handleCreate() {
    try {
      const id = await createConversation();
      await loadConversations();
      selectConversation(id);
    } catch (error) {
      console.error('Failed to create conversation:', error);
    }
  }

  async function handleDelete(id: string, event: Event) {
    event.stopPropagation();
    if (!confirm('Delete this conversation?')) return;

    try {
      await deleteConversation(id);
      if (selectedId === id) {
        selectedId = null;
      }
      await loadConversations();
    } catch (error) {
      console.error('Failed to delete conversation:', error);
    }
  }

  function selectConversation(id: string) {
    selectedId = id;
    onSelect(id);
  }
</script>

<div class="conversation-list">
  <div class="header">
    <h2>Conversations</h2>
    <button onclick={handleCreate} class="btn-primary">
      New Chat
    </button>
  </div>

  {#if loading}
    <div class="loading">Loading...</div>
  {:else if conversations.length === 0}
    <div class="empty">
      <p>No conversations yet</p>
      <button onclick={handleCreate} class="btn-secondary">
        Start your first chat
      </button>
    </div>
  {:else}
    <ul class="list">
      {#each conversations as conv (conv.id)}
        <li
          class="item"
          class:active={selectedId === conv.id}
          onclick={() => selectConversation(conv.id)}
        >
          <div class="item-content">
            <div class="title">{conv.title}</div>
            <div class="time">{new Date(conv.updated_at).toLocaleString()}</div>
          </div>
          <button
            class="btn-delete"
            onclick={(e) => handleDelete(conv.id, e)}
            aria-label="Delete conversation"
          >
            ×
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</div>

<style>
  .conversation-list {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: #F7F5F1;
    border-right: 1px solid #E7E3DA;
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1rem;
    border-bottom: 1px solid #E7E3DA;
  }

  h2 {
    margin: 0;
    font-size: 1.25rem;
    font-weight: 500;
    color: #1E2227;
  }

  .btn-primary {
    padding: 0.5rem 1rem;
    background: #3C5A78;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.875rem;
    font-weight: 500;
    transition: background 0.2s;
  }

  .btn-primary:hover {
    background: #2E4760;
  }

  .btn-secondary {
    padding: 0.5rem 1rem;
    background: white;
    color: #3C5A78;
    border: 1px solid #E7E3DA;
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.875rem;
    transition: all 0.2s;
  }

  .btn-secondary:hover {
    background: #F7F5F1;
  }

  .loading,
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    flex: 1;
    padding: 2rem;
    color: #6B7077;
  }

  .empty p {
    margin: 0 0 1rem;
  }

  .list {
    list-style: none;
    padding: 0;
    margin: 0;
    overflow-y: auto;
    flex: 1;
  }

  .item {
    display: flex;
    align-items: center;
    padding: 0.75rem 1rem;
    cursor: pointer;
    border-bottom: 1px solid #E7E3DA;
    transition: background 0.2s;
  }

  .item:hover {
    background: white;
  }

  .item.active {
    background: white;
    border-left: 3px solid #3C5A78;
  }

  .item-content {
    flex: 1;
    min-width: 0;
  }

  .title {
    font-weight: 500;
    color: #1E2227;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .time {
    font-size: 0.75rem;
    color: #6B7077;
    margin-top: 0.25rem;
  }

  .btn-delete {
    width: 1.5rem;
    height: 1.5rem;
    border: none;
    background: transparent;
    color: #6B7077;
    font-size: 1.5rem;
    line-height: 1;
    cursor: pointer;
    border-radius: 4px;
    transition: all 0.2s;
  }

  .btn-delete:hover {
    background: #E7E3DA;
    color: #1E2227;
  }
</style>
