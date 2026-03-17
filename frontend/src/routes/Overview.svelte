<script lang="ts">
  import Section from '$lib/components/Section.svelte';
  import MetricCard from '$lib/components/MetricCard.svelte';
  import Icon from '$lib/components/Icon.svelte';
  import { logsStore, uiStore } from '$lib/stores';

  let helpVisible = $state(false);

  async function copyText(text: string) {
    await uiStore.copyToClipboard(text);
  }
</script>

<div class="dashboard-page">
  <div class="metrics-grid">
    <MetricCard 
      title="Total Requests" 
      value={logsStore.total} 
      label="Since startup"
    >
      {#snippet icon()}
        <Icon name="activity" size={20} />
      {/snippet}
    </MetricCard>

    <MetricCard 
      title="All Log Files" 
      value={logsStore.totalAll} 
      label="In logs folder"
    >
      {#snippet icon()}
        <Icon name="grid" size={20} />
      {/snippet}
    </MetricCard>

    <MetricCard 
      title="Parsed Texts" 
      value={logsStore.parsedTotal} 
      label="All versions"
    >
      {#snippet icon()}
        <Icon name="layers" size={20} />
      {/snippet}
    </MetricCard>

    <MetricCard 
      title="Server Port" 
      value={uiStore.port} 
      label="Listening on"
    >
      {#snippet icon()}
        <Icon name="server" size={20} />
      {/snippet}
    </MetricCard>
  </div>

  <Section id="endpoints" title="Endpoints">
    <div class="config-grid">
      <div class="config-card">
        <div class="config-header">
          <span class="config-label">Model Name</span>
          <span class="config-hint">For JanitorAI</span>
        </div>
        <div class="config-row">
          <input 
            type="text" 
            class="input input-mono" 
            value="nvidia/nemotron-3-super-120b-a12b:free" 
            readonly 
            aria-label="Model Name Preset" 
          />
          <button 
            class="btn btn-accent" 
            onclick={() => copyText('nvidia/nemotron-3-super-120b-a12b:free')}
            aria-label="Copy model name"
          >
            <Icon name="copy" size={14} />
          </button>
        </div>
      </div>

      <div class="config-card" class:highlight={uiStore.cloudflareUrl}>
        <div class="config-header">
          <span class="config-label">Cloudflare Endpoint</span>
          <span class="config-hint">Public URL</span>
          </div>
        <div class="config-row">
          <input 
            type="text" 
            class="input input-mono" 
            value={uiStore.cloudflareUrl || 'Not available'} 
            readonly 
            aria-label="Cloudflare Endpoint" 
          />
          <button 
            class="btn btn-accent" 
            onclick={() => copyText(uiStore.cloudflareUrl)}
            disabled={!uiStore.cloudflareUrl}
            aria-label="Copy Cloudflare Endpoint"
          >
            <Icon name="copy" size={14} />
          </button>
        </div>
      </div>

      <div class="config-card">
        <div class="config-header">
          <span class="config-label">Local Endpoint</span>
          <span class="config-hint">This machine only</span>
          </div>
        <div class="config-row">
          <input 
            type="text" 
            class="input input-mono" 
            value={uiStore.localUrl} 
            readonly 
            aria-label="Local Endpoint" 
          />
          <button 
            class="btn btn-accent" 
            onclick={() => copyText(uiStore.localUrl)}
            aria-label="Copy Local Endpoint"
          >
            <Icon name="copy" size={14} />
          </button>
        </div>
        </div>
      </div>
    </Section>

  <Section id="quickstart" title="Quick Start">
    <ol class="steps">
      <li>
        <span class="step-number">1</span>
        <div class="step-content">
          <p>Open your character chat in JanitorAI.</p>
        </div>
      </li>
      <li>
        <span class="step-number">2</span>
        <div class="step-content">
          <p>Turn on <strong>Using proxy</strong> and create a new proxy profile.</p>
        </div>
      </li>
      <li>
        <span class="step-number">3</span>
        <div class="step-content">
          <p>Set <strong>Model name</strong> to: <code>nvidia/nemotron-3-super-120b-a12b:free</code></p>
        </div>
      </li>
      <li>
        <span class="step-number">4</span>
        <div class="step-content">
          <p>Set <strong>Proxy URL</strong> to the Cloudflare endpoint shown above.</p>
        </div>
      </li>
      <li>
        <span class="step-number">5</span>
        <div class="step-content">
          <p>
            Set <strong>API Key</strong> to your OpenRouter key.
            <button 
              type="button" 
              class="help-trigger" 
              onclick={() => helpVisible = !helpVisible}
              aria-expanded={helpVisible}
              aria-controls="openrouterApiHelp" 
            >
              <Icon name="info" size={12} />
              How to get one?
            </button>
          </p>
          {#if helpVisible}
            <div id="openrouterApiHelp" class="help-card">
              <p>
                Log in at <a href="https://openrouter.ai" target="_blank" rel="noreferrer noopener">openrouter.ai</a>, 
                open <strong>Keys</strong> from your profile menu, click <strong>Create API Key</strong>, then copy it.
              </p>
            </div>
  {/if}
        </div>
      </li>
      <li>
        <span class="step-number">6</span>
        <div class="step-content">
          <p>Save changes and <strong>Save Settings</strong> in JanitorAI, then refresh this page.</p>
        </div>
      </li>
      <li>
        <span class="step-number">7</span>
        <div class="step-content">
          <p>Send a quick test message (e.g., "Hi") to verify the connection.</p>
        </div>
      </li>
    </ol>
  </Section>
</div>

<style>
  .dashboard-page {
    animation: fadeInUp var(--duration-normal) var(--ease-out);
  }

  .metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: var(--space-lg);
    margin-bottom: var(--space-xl);
  }

  .metrics-grid > :global(*) {
    opacity: 0;
    animation: fadeInUp var(--duration-normal) var(--ease-out) forwards;
  }

  .metrics-grid > :global(*:nth-child(1)) { animation-delay: 0.05s; }
  .metrics-grid > :global(*:nth-child(2)) { animation-delay: 0.1s; }
  .metrics-grid > :global(*:nth-child(3)) { animation-delay: 0.15s; }
  .metrics-grid > :global(*:nth-child(4)) { animation-delay: 0.2s; }

  /* Config cards */
  .config-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: var(--space-md);
  }

  .config-card {
    background: var(--bg-elevated);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-lg);
    padding: var(--space-lg) var(--space-xl);
    transition: border-color var(--duration-fast);
  }

  .config-card.highlight {
    border-color: var(--accent-border);
  }

  .config-header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-bottom: var(--space-md);
    gap: var(--space-sm);
  }

  .config-label {
    font-size: 0.9375rem;
    font-weight: 600;
    color: var(--text-primary);
  }

  .config-hint {
    font-size: 0.75rem;
    color: var(--text-muted);
    flex-shrink: 0;
  }

  .config-row {
    display: flex;
    gap: var(--space-sm);
  }

  .config-row .input {
    flex: 1;
    min-width: 0;
  }

  /* Steps list */
  .steps {
    list-style: none;
    counter-reset: step-counter;
  }

  .steps li {
    display: flex;
    gap: var(--space-md);
    padding: var(--space-sm) 0;
    border-bottom: 1px solid var(--border-subtle);
  }

  .steps li:last-child {
    border-bottom: none;
  }

  .step-number {
    width: 24px;
    height: 24px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius-full);
    background: var(--bg-hover);
    color: var(--text-muted);
    font-size: 0.75rem;
    font-weight: 600;
    flex-shrink: 0;
  }

  .step-content {
    flex: 1;
    padding-top: 2px;
    min-width: 0;
  }

  .step-content p {
    color: var(--text-secondary);
    line-height: 1.5;
  }

  .step-content strong {
    color: var(--text-primary);
    font-weight: 500;
  }

  .step-content code {
    display: inline-block;
    background: var(--accent-subtle);
    padding: 2px 6px;
    border-radius: var(--radius-sm);
    font-family: 'Geist Mono', monospace;
    font-size: 0.8125rem;
    color: var(--accent);
    word-break: break-all;
  }

  .step-content a {
    color: var(--accent);
    text-decoration: none;
    font-weight: 500;
  }

  .step-content a:hover {
    text-decoration: underline;
  }

  .help-trigger {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin-left: var(--space-xs);
    padding: 3px 8px;
    border: none;
    background: var(--bg-hover);
    border-radius: var(--radius-sm);
    color: var(--text-muted);
    font-size: 0.75rem;
    font-weight: 500;
    cursor: pointer;
    transition: color var(--duration-fast), background-color var(--duration-fast);
    -webkit-tap-highlight-color: transparent;
  }

  .help-trigger:hover {
    color: var(--text-primary);
    background: var(--bg-active);
  }

  .help-card {
    margin-top: var(--space-sm);
    padding: var(--space-sm) var(--space-md);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    animation: fadeInUp var(--duration-fast) var(--ease-out);
  }

  .help-card p {
    font-size: 0.8125rem;
  }

  /* Tablet breakpoint */
  @media (max-width: 1023px) {
    .metrics-grid {
      grid-template-columns: repeat(2, 1fr);
      gap: var(--space-md);
    }

    .config-grid {
      grid-template-columns: 1fr;
    }
  }

  /* Mobile breakpoint */
  @media (max-width: 767px) {
    .metrics-grid {
      display: flex;
      overflow-x: auto;
      scroll-snap-type: x mandatory;
      -webkit-overflow-scrolling: touch;
      scrollbar-width: none;
      -ms-overflow-style: none;
      gap: var(--space-md);
      margin-left: calc(-1 * var(--space-md));
      margin-right: calc(-1 * var(--space-md));
      padding-left: var(--space-md);
      padding-right: var(--space-md);
      margin-bottom: var(--space-lg);
    }

    .metrics-grid::-webkit-scrollbar {
      display: none;
    }

    .metrics-grid > :global(*) {
      scroll-snap-align: start;
      flex: 0 0 75%;
      min-width: 220px;
      max-width: 280px;
    }

    .config-card {
      padding: var(--space-md);
      border-radius: var(--radius-md);
    }

    .config-label {
      font-size: 0.875rem;
    }

    .config-row {
      flex-direction: column;
      gap: var(--space-sm);
    }

    .config-row .btn {
      width: 100%;
    }

    .steps li {
      gap: var(--space-sm);
      padding: var(--space-md) 0;
    }

    .step-number {
      width: 22px;
      height: 22px;
      font-size: 0.6875rem;
    }

    .step-content p {
      font-size: 0.875rem;
    }

    .step-content code {
      font-size: 0.75rem;
      padding: 2px 4px;
    }

    .help-trigger {
      margin-left: 0;
      margin-top: var(--space-xs);
      display: flex;
      width: fit-content;
    }
  }

  /* Small mobile breakpoint */
  @media (max-width: 479px) {
    .metrics-grid > :global(*) {
      flex: 0 0 85%;
      min-width: 200px;
    }

    .config-card {
      padding: var(--space-sm) var(--space-md);
    }

    .config-header {
      flex-direction: column;
      gap: var(--space-xs);
      margin-bottom: var(--space-sm);
    }

    .step-content p {
      font-size: 0.8125rem;
    }

    .help-card {
      padding: var(--space-xs) var(--space-sm);
    }

    .help-card p {
      font-size: 0.75rem;
    }
  }
</style>
