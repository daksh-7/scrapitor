<script lang="ts">
  import Section from '$lib/components/Section.svelte';
  import LogItem from '$lib/components/LogItem.svelte';
  import Modal from '$lib/components/Modal.svelte';
  import ConfirmModal from '$lib/components/ConfirmModal.svelte';
  import Icon from '$lib/components/Icon.svelte';
  import { logsStore, parserStore, uiStore } from '$lib/stores';
  import { exportToSillyTavern } from '$lib/api';

  let filterText = $state('');
  let logModalOpen = $state(false);
  let logModalTitle = $state('');
  let logModalContent = $state('');
  let logModalFormat = $state<'json' | 'txt'>('json');
  let parsedModalOpen = $state(false);
  let parsedModalTitle = $state('');
  let parsedVersions = $state<Array<{file: string; mtime: number; size: number}>>([]);
  let parsedModalLogName = $state('');
  let confirmOpen = $state(false);
  let confirmMessage = $state('');
  let confirmAction = $state<() => void>(() => {});
  
  let renamingParsedFile = $state<string | null>(null);
  let parsedRenameValue = $state('');
  let parsedRenameInputRef = $state<HTMLInputElement | null>(null);
  let selectedParsedFiles = $state<Set<string>>(new Set());
  let selectingParsedFiles = $state(false);

  const filterLower = $derived(filterText.toLowerCase());

  const filteredLogs = $derived(
    filterText
      ? logsStore.logs.filter(name => name.toLowerCase().includes(filterLower))
      : logsStore.logs
  );

  const visibleLogs = $derived(filteredLogs.slice(0, 100));

  function highlightJson(content: string): string {
    const escaped = content
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
    
    return escaped
      .replace(/"([^"\\]*(\\.[^"\\]*)*)"\s*:/g, '<span class="json-key">"$1"</span>:')
      .replace(/:\s*"([^"\\]*(\\.[^"\\]*)*)"/g, ': <span class="json-string">"$1"</span>')
      .replace(/:\s*(-?\d+\.?\d*(?:[eE][+-]?\d+)?)\b/g, ': <span class="json-number">$1</span>')
      .replace(/:\s*(true|false)\b/g, ': <span class="json-boolean">$1</span>')
      .replace(/:\s*(null)\b/g, ': <span class="json-null">$1</span>')
      .replace(/\[\s*(-?\d+\.?\d*(?:[eE][+-]?\d+)?)\b/g, '[<span class="json-number">$1</span>')
      .replace(/,\s*(-?\d+\.?\d*(?:[eE][+-]?\d+)?)\b/g, ', <span class="json-number">$1</span>');
  }

  async function openLog(name: string) {
    logModalTitle = name;
    logModalContent = 'Loading…';
    logModalFormat = 'json';
    logModalOpen = true;

    try {
      const content = await logsStore.getContent(name);
      logModalContent = content;
    } catch (e) {
      logModalContent = `Error: ${e instanceof Error ? e.message : 'Failed to load'}`;
    }
  }

  async function openParsedList(name: string) {
    parsedModalLogName = name;
    parsedModalTitle = `${name} — TXT`;
    parsedVersions = [];
    renamingParsedFile = null;
    parsedModalOpen = true;

    try {
      const data = await logsStore.getParsedVersions(name);
      parsedVersions = data.versions;
      if (!parsedVersions.length) {
        uiStore.notify('No parsed TXT versions yet', 'info');
        parsedModalOpen = false;
      }
    } catch {
      parsedModalOpen = false;
    }
  }

  async function refreshParsedList() {
    try {
      logsStore.clearCachesFor([parsedModalLogName]);
      const data = await logsStore.getParsedVersions(parsedModalLogName);
      parsedVersions = data.versions;
    } catch {}
  }

  async function openParsedContent(logName: string, fileName: string) {
    logModalTitle = `${logName} — ${fileName}`;
    logModalContent = 'Loading…';
    logModalFormat = 'txt';
    logModalOpen = true;

    try {
      const content = await logsStore.getParsedText(logName, fileName);
      logModalContent = content;
    } catch (e) {
      logModalContent = `Error: ${e instanceof Error ? e.message : 'Failed to load'}`;
    }
  }

  function startDeleteSelection() {
    logsStore.startSelection('delete');
  }

  function cancelSelection() {
    logsStore.cancelSelection();
  }

  async function deleteSelected() {
    const count = logsStore.selectedCount;
    if (count === 0) {
      uiStore.notify('No files selected', 'info');
      return;
    }
    confirmMessage = `Delete ${count} log${count === 1 ? '' : 's'}? This cannot be undone.`;
    confirmAction = async () => {
      const deleted = await logsStore.deleteSelected();
      uiStore.notify(`Deleted ${deleted} log${deleted === 1 ? '' : 's'}`);
    };
    confirmOpen = true;
  }

  async function rewriteSelected() {
    const files = [...logsStore.selectedLogs];
    if (files.length === 0) {
      uiStore.notify('No files selected', 'info');
      return;
    }
    try {
      const result = await parserStore.rewrite('custom', files);
      uiStore.notify(`Wrote ${result.rewritten} file(s)`);
      logsStore.cancelSelection();
      await logsStore.refresh();
    } catch {}
  }

  function formatDate(mtime: number): string {
    if (!mtime) return '';
    return new Date(mtime * 1000).toISOString().slice(0, 19).replace('T', ' ');
  }

  function formatSize(size: number): string {
    return `${Math.max(1, Math.round(size / 1024))} KB`;
  }

  function startParsedRename(fileName: string) {
    parsedRenameValue = fileName.replace(/\.txt$/, '');
    renamingParsedFile = fileName;
    setTimeout(() => {
      parsedRenameInputRef?.focus();
      parsedRenameInputRef?.select();
    }, 0);
  }

  async function commitParsedRename() {
    if (!renamingParsedFile) return;
    
    const newBasename = parsedRenameValue.trim();
    if (!newBasename || newBasename === renamingParsedFile.replace(/\.txt$/, '')) {
      cancelParsedRename();
      return;
    }
    
    const newName = newBasename + '.txt';
    try {
      await logsStore.renameParsed(parsedModalLogName, renamingParsedFile, newName);
      uiStore.notify(`Renamed to ${newName}`);
      await refreshParsedList();
    } catch (e) {
      uiStore.notify(e instanceof Error ? e.message : 'Rename failed', 'error');
    }
    renamingParsedFile = null;
  }

  function cancelParsedRename() {
    renamingParsedFile = null;
    parsedRenameValue = '';
  }

  function handleParsedRenameKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      e.preventDefault();
      commitParsedRename();
    } else if (e.key === 'Escape') {
      e.preventDefault();
      cancelParsedRename();
    }
  }

  function handleParsedRenameBlur() {
    setTimeout(() => {
      if (renamingParsedFile) {
        commitParsedRename();
      }
    }, 100);
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

  async function exportSelectedLogs() {
    const logNames = [...logsStore.selectedLogs];
    if (logNames.length === 0) {
      uiStore.notify('No files selected', 'info');
      return;
    }
    try {
      const exportResult = await parserStore.exportSillyTavernFromTxt(logNames);
      
      if (exportResult.exports.length > 0) {
        for (const exp of exportResult.exports) {
          downloadJson(exp.json, exp.filename);
        }
        uiStore.notify(`Exported ${exportResult.count} file(s) to SillyTavern`);
      } else {
        uiStore.notify('No parsed TXT files found for selected logs', 'info');
      }
      logsStore.cancelSelection();
    } catch (e) {
      uiStore.notify(e instanceof Error ? e.message : 'Export failed', 'error');
    }
  }

  function toggleParsedFileSelection(fileName: string) {
    const newSet = new Set(selectedParsedFiles);
    if (newSet.has(fileName)) {
      newSet.delete(fileName);
    } else {
      newSet.add(fileName);
    }
    selectedParsedFiles = newSet;
  }

  function toggleSelectAllParsed() {
    if (selectedParsedFiles.size === parsedVersions.length) {
      selectedParsedFiles = new Set();
    } else {
      selectedParsedFiles = new Set(parsedVersions.map(v => v.file));
    }
  }

  function startParsedExportSelection() {
    selectingParsedFiles = true;
    selectedParsedFiles = new Set();
  }

  function cancelParsedExportSelection() {
    selectingParsedFiles = false;
    selectedParsedFiles = new Set();
  }

  async function exportSelectedParsedFiles() {
    const files = [...selectedParsedFiles];
    if (files.length === 0) {
      uiStore.notify('No files selected', 'info');
      return;
    }
    try {
      const result = await exportToSillyTavern({
        log_name: parsedModalLogName,
        txt_files: files,
      });
      
      if (result.exports.length > 0) {
        for (const exp of result.exports) {
          downloadJson(exp.json, exp.filename);
        }
        uiStore.notify(`Exported ${result.count} file(s) to SillyTavern`);
      } else {
        uiStore.notify('No exports generated', 'info');
      }
      cancelParsedExportSelection();
    } catch (e) {
      uiStore.notify(e instanceof Error ? e.message : 'Export failed', 'error');
    }
  }
</script>

<div class="activity-page">
  <Section id="logs">
    <div class="logs-header">
      <div class="input-group">
        <input
          class="input"
          placeholder="Filter logs..."
          aria-label="Filter logs by name"
          bind:value={filterText}
        />
        <button class="btn btn-icon-mobile" onclick={() => logsStore.refresh()} title="Refresh">
          <Icon name="refresh" size={14} />
          <span class="btn-label">Refresh</span>
        </button>
      </div>
      
      <div class="logs-actions">
        {#if logsStore.selectingLogs}
          <div class="selection-bar">
            <span class="selection-count">
              {logsStore.selectedCount} selected
            </span>
            <button class="btn btn-sm" onclick={() => logsStore.toggleSelectAll()}>
              <Icon name="checkSquare" size={12} />
              {visibleLogs.every(n => logsStore.selectedLogs.has(n)) ? 'Deselect All' : 'Select All'}
            </button>
            {#if logsStore.selectionAction === 'write'}
              <button class="btn btn-sm btn-accent" onclick={rewriteSelected}>
                <Icon name="write" size={12} />
                Write Selected
              </button>
            {:else if logsStore.selectionAction === 'export'}
              <button class="btn btn-sm btn-accent" onclick={exportSelectedLogs}>
                <Icon name="export" size={12} />
                Export Selected
              </button>
            {:else}
              <button class="btn btn-sm btn-danger" onclick={deleteSelected}>
                <Icon name="trash" size={12} />
                Delete Selected
              </button>
            {/if}
            <button class="btn btn-sm" onclick={cancelSelection}>
              Cancel
            </button>
          </div>
        {:else}
          <button class="btn btn-secondary" onclick={() => logsStore.startSelection('export')}>
            <Icon name="export" size={14} />
            Export...
          </button>
          <button class="btn btn-danger" onclick={startDeleteSelection}>
            <Icon name="trash" size={14} />
            Delete...
          </button>
        {/if}
      </div>
    </div>

    <div class="logs-container">
      {#if visibleLogs.length === 0}
        <div class="empty-state">
          <Icon name="clock" size={48} class="empty-icon" />
          <p class="empty-title">No logs yet</p>
          <p class="empty-description">Logs will appear here when you send requests through the proxy.</p>
        </div>
      {:else}
        {#each visibleLogs as name (name)}
          <LogItem 
            {name}
            selectable={logsStore.selectingLogs}
            selected={logsStore.selectedLogs.has(name)}
            onclick={() => logsStore.selectingLogs ? logsStore.toggleSelection(name) : openLog(name)}
            onOpenParsed={() => openParsedList(name)}
          />
        {/each}
        {#if filteredLogs.length > 100}
          <div class="truncation-notice">
            Showing first 100 of {filteredLogs.length} logs
          </div>
        {/if}
      {/if}
    </div>
  </Section>
</div>

<!-- Log Content Modal -->
<Modal 
  open={logModalOpen} 
  title={logModalTitle} 
  onClose={() => logModalOpen = false}
  onBack={parsedModalOpen ? () => { logModalOpen = false; openParsedList(parsedModalLogName); } : undefined}
  format={logModalFormat}
>
  {#snippet children()}
    {#if logModalFormat === 'json' && logModalContent !== 'Loading…' && !logModalContent.startsWith('Error:')}
      {@html highlightJson(logModalContent)}
    {:else}
      {logModalContent}
    {/if}
  {/snippet}
</Modal>

<!-- Parsed Versions Modal -->
<Modal
  open={parsedModalOpen}
  title={parsedModalTitle}
  onClose={() => { parsedModalOpen = false; renamingParsedFile = null; cancelParsedExportSelection(); }}
>
  {#snippet children()}
    <div class="version-picker">
      <div class="version-toolbar">
        {#if selectingParsedFiles}
          <span class="selection-count">
            {selectedParsedFiles.size} selected
          </span>
          <button class="btn btn-sm" onclick={toggleSelectAllParsed}>
            <Icon name="checkSquare" size={12} />
            {selectedParsedFiles.size === parsedVersions.length ? 'Deselect All' : 'Select All'}
          </button>
          <button class="btn btn-sm btn-accent" onclick={exportSelectedParsedFiles}>
            <Icon name="export" size={12} />
            Export
          </button>
          <button class="btn btn-sm" onclick={cancelParsedExportSelection}>
            Cancel
          </button>
        {:else}
          <p class="version-header">Select a version to view:</p>
          <button class="btn btn-sm" onclick={startParsedExportSelection}>
            <Icon name="export" size={12} />
            Export...
          </button>
        {/if}
      </div>
      <div class="version-list">
        {#each parsedVersions as version (version.file)}
          <div class="version-item" class:renaming={renamingParsedFile === version.file} class:selecting={selectingParsedFiles} class:selected={selectedParsedFiles.has(version.file)}>
            {#if renamingParsedFile === version.file}
              <div class="version-rename-wrapper">
                <input 
                  type="text"
                  class="version-rename-input"
                  bind:this={parsedRenameInputRef}
                  bind:value={parsedRenameValue}
                  onkeydown={handleParsedRenameKeydown}
                  onblur={handleParsedRenameBlur}
                />
                <span class="version-rename-ext">.txt</span>
              </div>
              <div class="version-actions">
                <button 
                  class="version-action-btn"
                  onclick={() => commitParsedRename()}
                  title="Save"
                >
                  <Icon name="check" size={12} />
                </button>
                <button 
                  class="version-action-btn"
                  onclick={() => cancelParsedRename()}
                  title="Cancel"
                >
                  <Icon name="close" size={12} />
                </button>
              </div>
            {:else if selectingParsedFiles}
              <label class="version-select-wrapper">
                <input 
                  type="checkbox"
                  checked={selectedParsedFiles.has(version.file)}
                  onchange={() => toggleParsedFileSelection(version.file)}
                />
                <span class="version-name mono">{version.file}</span>
                <span class="version-meta">{formatDate(version.mtime)} · {formatSize(version.size)}</span>
              </label>
            {:else}
              <button 
                class="version-content"
                onclick={() => { parsedModalOpen = false; openParsedContent(parsedModalLogName, version.file); }}
              >
                <span class="version-name mono">{version.file}</span>
                <span class="version-meta">{formatDate(version.mtime)} · {formatSize(version.size)}</span>
              </button>
              <button 
                class="version-action-btn version-action-btn--hover"
                onclick={() => startParsedRename(version.file)}
                title="Rename"
              >
                <Icon name="edit" size={12} />
              </button>
            {/if}
          </div>
        {/each}
      </div>
    </div>
  {/snippet}
</Modal>

<!-- Confirm Modal -->
<ConfirmModal 
  open={confirmOpen}
  title="Delete Logs"
  message={confirmMessage}
  confirmText="Delete"
  cancelText="Cancel"
  danger={true}
  onConfirm={() => { confirmOpen = false; confirmAction(); }}
  onCancel={() => confirmOpen = false}
/>

<style>
  .activity-page {
    animation: fadeInUp var(--duration-normal) var(--ease-out);
  }

  .logs-header {
    display: flex;
    flex-direction: column;
    gap: var(--space-md);
    margin-bottom: var(--space-md);
  }

  .logs-header .input-group {
    max-width: 400px;
  }

  .logs-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--space-sm);
  }

  .selection-bar {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    flex-wrap: wrap;
  }

  .selection-count {
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--accent);
    padding: 4px 8px;
    background: var(--accent-subtle);
    border-radius: var(--radius-sm);
  }

  .logs-container {
    background: var(--bg-elevated);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-md);
    padding: var(--space-sm);
    max-height: min(60vh, 600px);
    overflow-y: auto;
    -webkit-overflow-scrolling: touch;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: var(--space-3xl) var(--space-xl);
    text-align: center;
  }

  .empty-state :global(.empty-icon) {
    color: var(--text-faint);
    margin-bottom: var(--space-lg);
    opacity: 0.5;
  }

  .empty-title {
    font-size: 1rem;
    font-weight: 600;
    color: var(--text-primary);
    margin-bottom: var(--space-xs);
  }

  .empty-description {
    font-size: 0.8125rem;
    color: var(--text-muted);
    max-width: 280px;
  }

  .truncation-notice {
    text-align: center;
    padding: var(--space-md);
    font-size: 0.75rem;
    color: var(--text-muted);
    border-top: 1px solid var(--border-subtle);
    margin-top: var(--space-sm);
  }

  /* Version picker */
  .version-picker {
    white-space: normal;
    word-break: normal;
  }

  .version-toolbar {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    margin-bottom: var(--space-md);
    flex-wrap: wrap;
  }

  .version-toolbar .selection-count {
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--accent);
    padding: 4px 8px;
    background: var(--accent-subtle);
    border-radius: var(--radius-sm);
  }

  .version-header {
    font-weight: 500;
    color: var(--text-secondary);
    margin: 0;
    flex: 1;
  }

  .version-list {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .version-item {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    padding: var(--space-sm) var(--space-md);
    background: var(--bg-surface);
    border: 1px solid var(--border-default);
    border-radius: var(--radius-md);
    transition:
      border-color var(--duration-fast),
      background-color var(--duration-fast);
  }

  .version-item:hover {
    border-color: var(--accent-border);
    background: var(--accent-subtle);
  }

  .version-item.renaming {
    border-color: var(--accent);
    background: var(--bg-hover);
  }

  .version-item.selecting {
    cursor: pointer;
  }

  .version-item.selecting.selected {
    border-color: var(--accent);
    background: var(--accent-subtle);
  }

  .version-select-wrapper {
    display: flex;
    align-items: center;
    gap: var(--space-sm);
    flex: 1;
    min-width: 0;
    cursor: pointer;
  }

  .version-select-wrapper input[type="checkbox"] {
    flex-shrink: 0;
    cursor: pointer;
  }

  .version-select-wrapper .version-name {
    flex: 1;
    min-width: 0;
  }

  .version-content {
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex: 1;
    min-width: 0;
    gap: var(--space-md);
    background: none;
    border: none;
    padding: 0;
    cursor: pointer;
    text-align: left;
  }

  .version-name {
    font-size: 0.8125rem;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .version-meta {
    font-size: 0.75rem;
    color: var(--text-muted);
    flex-shrink: 0;
  }

  /* Inline rename for parsed files */
  .version-rename-wrapper {
    display: flex;
    align-items: center;
    flex: 1;
    min-width: 0;
  }

  .version-rename-input {
    flex: 1;
    min-width: 0;
    padding: 2px 6px;
    border: 1px solid var(--accent);
    border-radius: var(--radius-sm);
    background: var(--bg-surface);
    color: var(--text-primary);
    font-family: 'Geist Mono', monospace;
    font-size: 0.8125rem;
    font-weight: 500;
    outline: none;
  }

  .version-rename-input:focus {
    box-shadow: 0 0 0 2px var(--accent-subtle);
  }

  .version-rename-ext {
    font-family: 'Geist Mono', monospace;
    font-size: 0.8125rem;
    color: var(--text-muted);
    margin-left: 2px;
    flex-shrink: 0;
  }

  .version-actions {
    display: flex;
    gap: var(--space-xs);
    flex-shrink: 0;
  }

  .version-action-btn {
    width: 22px;
    height: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    color: var(--text-muted);
    border-radius: var(--radius-sm);
    cursor: pointer;
    transition:
      color var(--duration-fast),
      background-color var(--duration-fast);
    flex-shrink: 0;
    -webkit-tap-highlight-color: transparent;
  }

  .version-action-btn:hover {
    color: var(--text-primary);
    background: var(--bg-active);
  }

  .version-action-btn--hover {
    opacity: 0;
  }

  .version-item:hover .version-action-btn--hover {
    opacity: 1;
  }

  /* ═══════════════════════════════════════════════════════════
     Mobile Optimizations
     ═══════════════════════════════════════════════════════════ */

  /* Tablet breakpoint */
  @media (max-width: 1023px) {
    .logs-container {
      max-height: min(55vh, 500px);
    }
  }

  /* Mobile breakpoint */
  @media (max-width: 767px) {
    /* Header - full width stacked layout */
    .logs-header {
      gap: var(--space-md);
    }

    .logs-header .input-group {
      max-width: none;
      width: 100%;
    }

    .logs-header .input-group .input {
      flex: 1;
    }

    .logs-header .input-group .btn {
      flex-shrink: 0;
      padding: 0 var(--space-md);
    }

    /* Hide button label on mobile */
    .btn-icon-mobile .btn-label {
      display: none;
    }

    /* Actions area */
    .logs-actions {
      justify-content: stretch;
      width: 100%;
    }

    .logs-actions > .btn {
      width: 100%;
      justify-content: center;
    }

    /* Selection bar - redesigned for mobile */
    .selection-bar {
      width: 100%;
      background: var(--bg-elevated);
      border: 1px solid var(--accent-border);
      border-radius: var(--radius-lg);
      padding: var(--space-sm);
      gap: var(--space-sm);
    }

    .selection-count {
      font-size: 0.8125rem;
      padding: 6px 12px;
      border-radius: var(--radius-md);
      flex-shrink: 0;
    }

    .selection-bar .btn-sm {
      flex: 1;
      min-height: 40px;
      padding: var(--space-sm) var(--space-md);
      font-size: 0.75rem;
      justify-content: center;
      border-radius: var(--radius-md);
    }

    /* Logs container - maximize space */
    .logs-container {
      max-height: none;
      height: auto;
      flex: 1;
      padding: var(--space-xs);
      border-radius: var(--radius-lg);
      margin: 0 calc(-1 * var(--space-md));
      width: calc(100% + var(--space-md) * 2);
      border-left: none;
      border-right: none;
      border-radius: 0;
    }

    /* Empty state */
    .empty-state {
      padding: var(--space-2xl) var(--space-lg);
    }

    .empty-state :global(.empty-icon) {
      width: 56px;
      height: 56px;
    }

    .empty-title {
      font-size: 1rem;
    }

    .empty-description {
      font-size: 0.8125rem;
      max-width: 260px;
    }

    .truncation-notice {
      font-size: 0.75rem;
      padding: var(--space-md);
    }

    /* ── Version Picker Modal ─────────────────────────────── */
    .version-picker {
      padding-bottom: var(--space-md);
    }

    .version-toolbar {
      gap: var(--space-sm);
      padding-bottom: var(--space-sm);
      border-bottom: 1px solid var(--border-subtle);
      margin-bottom: var(--space-md);
    }

    .version-header {
      font-size: 0.875rem;
      width: 100%;
      margin-bottom: var(--space-xs);
    }

    .version-toolbar .btn-sm {
      flex: 1;
      min-height: 40px;
      justify-content: center;
      font-size: 0.75rem;
    }

    .version-toolbar .selection-count {
      width: 100%;
      text-align: center;
      margin-bottom: var(--space-xs);
    }

    .version-list {
      gap: var(--space-sm);
    }

    .version-item {
      padding: var(--space-md);
      border-radius: var(--radius-lg);
      min-height: 56px;
      gap: var(--space-md);
    }

    .version-item:active {
      transform: scale(0.98);
    }

    .version-content {
      flex-direction: column;
      align-items: flex-start;
      gap: 4px;
    }

    .version-name {
      font-size: 0.875rem;
      font-weight: 500;
      max-width: 100%;
    }

    .version-meta {
      font-size: 0.75rem;
      color: var(--text-faint);
    }

    .version-action-btn {
      width: 40px;
      height: 40px;
      border-radius: var(--radius-md);
      background: var(--bg-hover);
      opacity: 1;
    }

    .version-action-btn--hover {
      opacity: 1;
    }

    .version-action-btn:active {
      background: var(--bg-active);
    }

    /* Selecting mode */
    .version-select-wrapper {
      gap: var(--space-md);
      min-height: 40px;
    }

    .version-select-wrapper input[type="checkbox"] {
      width: 22px;
      height: 22px;
      accent-color: var(--accent);
    }

    .version-select-wrapper .version-name {
      flex: 1;
    }

    .version-select-wrapper .version-meta {
      display: none;
    }

    /* Rename mode */
    .version-rename-wrapper {
      flex: 1;
    }

    .version-rename-input {
      font-size: 16px;
      padding: var(--space-sm) var(--space-md);
      border-radius: var(--radius-md);
      min-height: 40px;
    }

    .version-rename-ext {
      font-size: 0.875rem;
      padding-left: var(--space-xs);
    }

    .version-actions {
      gap: var(--space-sm);
    }
  }

  /* Small mobile breakpoint */
  @media (max-width: 479px) {
    /* Selection bar - stack buttons */
    .selection-bar {
      flex-direction: column;
      align-items: stretch;
    }

    .selection-count {
      order: -1;
      text-align: center;
    }

    .selection-bar .btn-sm {
      width: 100%;
    }

    /* Logs container */
    .logs-container {
      margin: 0 calc(-1 * var(--space-sm));
      width: calc(100% + var(--space-sm) * 2);
    }

    /* Empty state compact */
    .empty-state {
      padding: var(--space-xl) var(--space-md);
    }

    .empty-state :global(.empty-icon) {
      width: 48px;
      height: 48px;
      margin-bottom: var(--space-md);
    }

    .empty-title {
      font-size: 0.9375rem;
    }

    .empty-description {
      font-size: 0.75rem;
    }

    /* Version picker compact */
    .version-toolbar .btn-sm {
      font-size: 0.6875rem;
      padding: var(--space-sm);
    }

    .version-item {
      padding: var(--space-sm) var(--space-md);
      min-height: 52px;
    }

    .version-name {
      font-size: 0.8125rem;
    }

    .version-meta {
      font-size: 0.6875rem;
    }

    .version-action-btn {
      width: 36px;
      height: 36px;
    }
  }
</style>
