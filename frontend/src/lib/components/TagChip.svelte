<script lang="ts">
  interface Props {
    tag: string;
    state: 'include' | 'exclude';
    onclick: () => void;
    onmouseenter?: () => void;
    onmouseleave?: () => void;
  }

  let { tag, state, onclick, onmouseenter, onmouseleave }: Props = $props();

  const displayName = $derived(
    tag.toLowerCase() === 'untagged content' ? 'Untagged Content' : tag
  );
</script>

<button
  class="tag-chip"
  class:include={state === 'include'}
  class:exclude={state === 'exclude'}
  title="Click to toggle"
  {onclick}
  {onmouseenter}
  {onmouseleave}
>
  <span class="tag-indicator"></span>
  <span class="tag-name">{displayName}</span>
</button>

<style>
  .tag-chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 5px 12px;
    border-radius: var(--radius-full);
    border: 1px solid var(--border-default);
    font-size: 0.8125rem;
    font-weight: 500;
    background: var(--bg-elevated);
    cursor: pointer;
    color: var(--text-secondary);
    transition:
      background-color var(--duration-fast) var(--ease-out),
      border-color var(--duration-fast) var(--ease-out),
      color var(--duration-fast) var(--ease-out),
      transform var(--duration-fast) var(--ease-out);
    -webkit-tap-highlight-color: transparent;
  }

  .tag-chip:hover {
    border-color: var(--border-strong);
    background: var(--bg-hover);
  }

  .tag-chip:active {
    transform: scale(0.97);
  }

  .tag-indicator {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--text-faint);
    transition: background-color var(--duration-fast);
    flex-shrink: 0;
  }

  .tag-chip.include {
    border-color: var(--accent-border);
    background: var(--accent-subtle);
    color: var(--accent);
  }

  .tag-chip.include .tag-indicator {
    background: var(--accent);
  }

  .tag-chip.exclude {
    border-color: var(--danger-border);
    background: var(--danger-subtle);
    color: var(--danger);
  }

  .tag-chip.exclude .tag-indicator {
    background: var(--danger);
  }

  .tag-name {
    max-width: 200px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* Mobile breakpoint */
  @media (max-width: 767px) {
    .tag-chip {
      padding: 8px 14px;
      font-size: 0.75rem;
      min-height: 36px;
    }

    .tag-indicator {
      width: 8px;
      height: 8px;
    }

    .tag-name {
      max-width: 150px;
    }
  }

  /* Small mobile breakpoint */
  @media (max-width: 479px) {
    .tag-chip {
      padding: 6px 10px;
      font-size: 0.6875rem;
    }

    .tag-name {
      max-width: 100px;
    }
  }
</style>
