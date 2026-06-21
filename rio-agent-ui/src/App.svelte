<script lang="ts">
  import ConversationList from './lib/ConversationList.svelte';
  import MessageView from './lib/MessageView.svelte';

  let selectedConversationId = $state<string | null>(null);

  function handleSelectConversation(id: string) {
    selectedConversationId = id;
  }
</script>

<main>
  <div class="app-container">
    <aside class="sidebar">
      <ConversationList onSelect={handleSelectConversation} />
    </aside>

    <section class="main-content">
      {#if selectedConversationId}
        <MessageView conversationId={selectedConversationId} />
      {:else}
        <div class="welcome">
          <h1>Rio Agent</h1>
          <p>Select a conversation or create a new one to get started</p>
        </div>
      {/if}
    </section>
  </div>
</main>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    font-family: Inter, system-ui, -apple-system, sans-serif;
    background: #FFFFFF;
    color: #1E2227;
  }

  :global(*) {
    box-sizing: border-box;
  }

  main {
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .app-container {
    display: flex;
    height: 100%;
  }

  .sidebar {
    width: 300px;
    flex-shrink: 0;
  }

  .main-content {
    flex: 1;
    overflow: hidden;
  }

  .welcome {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    text-align: center;
    padding: 2rem;
  }

  .welcome h1 {
    margin: 0 0 1rem;
    font-family: 'Playfair Display', serif;
    font-size: 3rem;
    font-weight: 500;
    color: #1E2227;
  }

  .welcome p {
    margin: 0;
    color: #6B7077;
    font-size: 1.125rem;
  }
</style>
