<script lang="ts">
  import Section from '$lib/components/Section.svelte';
  import TagChip from '$lib/components/TagChip.svelte';
  import Icon from '$lib/components/Icon.svelte';
  import { parserStore, logsStore, uiStore } from '$lib/stores';

  let newTagInput = $state('');
  let tagDetectModalOpen = $state(false);
  let tagDetectSelected = $state<Set<string>>(new Set());
  let writeModalOpen = $state(false);

  async function saveSettings() {
    try {
      await parserStore.save();
      uiStore.notify('Settings saved');
    } catch {}
  }

  async function detectLatest() {
    try {
      await parserStore.detectTags();
      uiStore.notify(`Detected ${parserStore.allTags.size} tags`);
    } catch {}
  }

  function openTagDetectModal() {
    tagDetectSelected = new Set();
    tagDetectModalOpen = true;
  }

  async function confirmTagDetect() {
    if (tagDetectSelected.size === 0) {
      uiStore.notify('Select at least one log', 'info');
      return;
    }
    try {
      await parserStore.detectTags([...tagDetectSelected]);
      uiStore.notify(`Detected ${parserStore.allTags.size} tags`);
      tagDetectModalOpen = false;
    } catch {}
  }

  function toggleTagDetectAll() {
    if (tagDetectSelected.size === logsStore.logs.length) {
      tagDetectSelected = new Set();
    } else {
      tagDetectSelected = new Set(logsStore.logs);
    }
  }

  async function writeLatest() {
    writeModalOpen = false;
    try {
      const result = await parserStore.rewrite('latest');
      uiStore.notify(`Wrote ${result.rewritten} file(s)`);
      await logsStore.refresh();
    } catch {}
  }

  function startCustomSelection() {
    writeModalOpen = false;
    logsStore.startSelection('write');
  }

  function addTag() {
    const tag = newTagInput.trim().toLowerCase();
    if (tag) {
      parserStore.addTag(tag);
      newTagInput = '';
      uiStore.notify(`Added tag: ${tag}`);
    }
  }

  function downloadJson(data: object, filename: string) {
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  async function exportLatest() {
    try {
      const writeResult = await parserStore.rewrite('latest');
      const logNames = writeResult.results.map(r => r.file);
      
      if (logNames.length === 0) {
        uiStore.notify(`Wrote ${writeResult.rewritten} file(s), no exports generated`, 'info');
        await logsStore.refresh();
        return;
      }
      
      const exportResult = await parserStore.exportSillyTavernFromTxt(logNames);
      
      if (exportResult.exports.length > 0) {
        for (const exp of exportResult.exports) {
          downloadJson(exp.json, exp.filename);
        }
        uiStore.notify(`Wrote ${writeResult.rewritten} file(s), exported ${exportResult.count} to SillyTavern`);
      } else {
        uiStore.notify(`Wrote ${writeResult.rewritten} file(s), no exports generated`, 'info');
      }
      await logsStore.refresh();
    } catch {}
  }
</script>

<div class="parser-page">
  <Section id="mode" title="Parser Mode">
    <div class="mode-selector">
      <button 
        class="mode-option"
        class:active={parserStore.mode === 'default'}
        onclick={() => parserStore.setMode('default')}
      >
        <span class="mode-name">Default</span>
        <span class="mode-desc">No tag filtering. Writes everything.</span>
      </button>
      <button 
        class="mode-option"
        class:active={parserStore.mode === 'custom'}
        onclick={() => parserStore.setMode('custom')}
      >
        <span class="mode-name">Custom</span>
        <span class="mode-desc">Use chips to Include/Exclude tags. Only included tags are written.</span>
      </button>
    </div>
  </Section>

  {#if parserStore.isCustomMode}
    <Section id="tags" title="Tags">
      <div class="tags-toolbar">
        <div class="input-group">
          <input 
            class="input" 
            placeholder="Add new tag..." 
            aria-label="New tag name"
            bind:value={newTagInput}
            onkeypress={(e) => e.key === 'Enter' && addTag()}
          />
          <button class="btn btn-primary" onclick={addTag}>Add</button>
        </div>
        <div class="action-bar">
          <button class="btn" onclick={() => parserStore.includeAll()}>
            <Icon name="check" size={14} />
            Include All
          </button>
          <button class="btn btn-danger" onclick={() => parserStore.excludeAll()}>
            <Icon name="close" size={14} />
            Clear All
          </button>
          <button class="btn btn-accent" onclick={detectLatest}>
            <Icon name="detect" size={14} />
            Detect Latest
          </button>
          <button class="btn" onclick={openTagDetectModal}>
            <Icon name="grid" size={14} />
            Detect From...
          </button>
        </div>
      </div>
      
      {#if parserStore.sortedTags.length > 0}
        <div class="tags-grid">
          {#each parserStore.sortedTags as tag}
            <TagChip 
              {tag}
              state={parserStore.getTagState(tag)}
              onclick={() => parserStore.cycleTagState(tag)}
            />
          {/each}
        </div>
      {:else}
        <div class="empty-tags">
          <p>No tags detected yet. Click "Detect Latest" to scan the most recent log.</p>
        </div>
      {/if}
    </Section>
  {/if}

  <div class="parser-actions">
    <button class="btn btn-primary" onclick={saveSettings}>
      <Icon name="save" size={14} />
      Save Settings
    </button>
    <button class="btn btn-accent" onclick={() => writeModalOpen = true}>
      <Icon name="write" size={14} />
      Write Output
    </button>
    <button class="btn btn-secondary" onclick={exportLatest}>
      <Icon name="download" size={14} />
      Export to SillyTavern
    </button>
  </div>
</div>

<!-- Tag Detect Modal -->
{#if tagDetectModalOpen}
  <div class="modal" role="dialog" aria-modal="true">
    <button class="modal-backdrop" onclick={() => tagDetectModalOpen = false} aria-label="Close modal"></button>
    <div class="modal-panel modal-panel--md">
      <div class="modal-header">
        <h2 class="modal-title">Detect Tags From Logs</h2>
        <div class="modal-actions">
          <button class="btn btn-ghost" onclick={() => tagDetectModalOpen = false}>
            <Icon name="close" size={14} />
          </button>
        </div>
      </div>
      <div class="modal-body">
        <div class="detect-toolbar">
          <button class="btn btn-sm btn-accent" onclick={confirmTagDetect}>
            <Icon name="detect" size={12} />
            Detect
          </button>
          <button class="btn btn-sm" onclick={toggleTagDetectAll}>
            <Icon name="checkSquare" size={12} />
            {tagDetectSelected.size === logsStore.logs.length ? 'Deselect All' : 'Select All'}
          </button>
          <button class="btn btn-sm" onclick={() => tagDetectSelected = new Set()}>
            <Icon name="close" size={12} />
            Clear
          </button>
        </div>
        <div class="detect-list">
          {#each logsStore.logs as log}
            <label class="detect-item">
              <input 
                type="checkbox" 
                checked={tagDetectSelected.has(log)}
                onchange={() => {
                  const newSet = new Set(tagDetectSelected);
                  if (newSet.has(log)) {
                    newSet.delete(log);
                  } else {
                    newSet.add(log);
                  }
                  tagDetectSelected = newSet;
                }}
              />
              <span class="mono">{log}</span>
            </label>
          {/each}
        </div>
      </div>
    </div>
  </div>
{/if}

<!-- Write Options Modal -->
{#if writeModalOpen}
  <div class="modal" role="dialog" aria-modal="true">
    <button class="modal-backdrop" onclick={() => writeModalOpen = false} aria-label="Close modal"></button>
    <div class="modal-panel modal-panel--sm">
      <div class="modal-header">
        <h2 class="modal-title">Write Output</h2>
        <div class="modal-actions">
          <button class="btn btn-ghost" onclick={() => writeModalOpen = false}>
            <Icon name="close" size={14} />
          </button>
        </div>
      </div>
      <div class="modal-body">
        <p class="write-description">
          Choose how to generate parsed TXT output from your logs.
        </p>
        <div class="write-options">
          <button class="write-option" onclick={writeLatest}>
            <span class="write-option-title">Write Latest</span>
            <span class="write-option-desc">Process the most recent log file</span>
          </button>
          <button class="write-option" onclick={startCustomSelection}>
            <span class="write-option-title">Custom Selection</span>
            <span class="write-option-desc">Choose specific files from Activity</span>
          </button>
        </div>
      </div>
    </div>
  </div>
{/if}

<style>
  .parser-page {
    animation: fadeInUp var(--duration-normal) var(--ease-out);
  }

  .mode-selector {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: var(--space-md);
  }

  .mode-option {
    display: flex;
    flex-direction: column;
    gap: var(--space-xs);
    padding: var(--space-md);
    background: var(--bg-elevated);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    cursor: pointer;
    text-align: left;
    transition: 
      border-color var(--duration-fast),
      background-color var(--duration-fast);
  }

  .mode-option:hover {
    border-color: var(--border-strong);
  }

  .mode-option.active {
    border-color: var(--accent);
    background: var(--accent-subtle);
  }

  .mode-name {
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--text-primary);
  }

  .mode-option.active .mode-name {
    color: var(--accent);
  }

  .mode-desc {
    font-size: 0.875rem;
    color: var(--text-muted);
    line-height: 1.4;
  }

  .tags-toolbar {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: var(--space-md);
    margin-bottom: var(--space-lg);
  }

  .tags-toolbar .input-group {
    flex: 0 0 auto;
    max-width: 300px;
  }

  .tags-grid {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-sm);
  }

  .empty-tags {
    padding: var(--space-xl);
    text-align: center;
    color: var(--text-muted);
    background: var(--bg-elevated);
    border-radius: var(--radius-md);
    border: 1px dashed var(--border-default);
    font-size: 0.875rem;
  }

  .parser-actions {
    display: flex;
    gap: var(--space-sm);
    margin-top: var(--space-lg);
  }

  .detect-toolbar {
    display: flex;
    gap: var(--space-sm);
    margin-bottom: var(--space-md);
  }

  .detect-list {
    max-height: 50vh;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .detect-item {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    padding: var(--space-xs) var(--space-sm);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition: background-color var(--duration-fast);
  }

  .detect-item:hover {
    background: var(--bg-hover);
  }

  .detect-item span {
    font-size: 0.875rem;
    color: var(--text-secondary);
  }

  .write-description {
    color: var(--text-secondary);
    margin-bottom: var(--space-lg);
    line-height: 1.5;
  }

  .write-options {
    display: flex;
    flex-direction: column;
    gap: var(--space-sm);
  }

  .write-option {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: var(--space-md);
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    cursor: pointer;
    text-align: left;
    transition: 
      border-color var(--duration-fast),
      background-color var(--duration-fast);
  }

  .write-option:hover {
    border-color: var(--accent-border);
    background: var(--accent-subtle);
  }

  .write-option-title {
    font-weight: 600;
    color: var(--text-primary);
    font-size: 0.875rem;
  }

  .write-option-desc {
    font-size: 0.8125rem;
    color: var(--text-muted);
  }

  /* Tablet breakpoint */
  @media (max-width: 1023px) {
    .mode-selector {
      grid-template-columns: repeat(2, 1fr);
    }
  }

  /* Mobile breakpoint */
  @media (max-width: 767px) {
    .mode-selector {
      grid-template-columns: 1fr;
      gap: var(--space-sm);
    }

    .mode-option {
      padding: var(--space-md);
    }

    .mode-name {
      font-size: 0.9375rem;
    }

    .mode-desc {
      font-size: 0.8125rem;
    }

    .tags-toolbar {
      flex-direction: column;
      gap: var(--space-sm);
    }

    .tags-toolbar .input-group {
      max-width: none;
      width: 100%;
    }

    .action-bar {
      width: 100%;
      flex-wrap: wrap;
      gap: var(--space-xs);
    }

    .action-bar .btn {
      flex: 1 1 calc(50% - var(--space-xs));
      min-width: 120px;
      justify-content: center;
    }

    .tags-grid {
      gap: var(--space-xs);
    }

    .empty-tags {
      padding: var(--space-lg);
      font-size: 0.8125rem;
    }

    .parser-actions {
      flex-direction: column;
      gap: var(--space-sm);
    }

    .parser-actions .btn {
      width: 100%;
    }

    /* Modal mobile adjustments */
    .detect-toolbar {
      flex-wrap: wrap;
      gap: var(--space-xs);
    }

    .detect-toolbar .btn-sm {
      flex: 1 1 auto;
      min-width: 80px;
      justify-content: center;
    }

    .detect-list {
      max-height: 40vh;
    }

    .detect-item {
      padding: var(--space-sm);
      min-height: var(--touch-target-min);
    }

    .detect-item span {
      font-size: 0.8125rem;
    }

    .write-description {
      font-size: 0.8125rem;
    }

    .write-options {
      gap: var(--space-sm);
    }

    .write-option {
      padding: var(--space-md);
    }

    .write-option-title {
      font-size: 0.9375rem;
    }

    .write-option-desc {
      font-size: 0.75rem;
    }
  }

  /* Small mobile breakpoint */
  @media (max-width: 479px) {
    .action-bar .btn {
      flex: 1 1 100%;
      min-width: 100%;
    }

    .mode-option {
      padding: var(--space-sm) var(--space-md);
    }

    .mode-desc {
      font-size: 0.75rem;
    }
  }
</style>
