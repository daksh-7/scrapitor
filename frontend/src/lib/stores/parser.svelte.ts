import { getParserSettings, saveParserSettings, getParserTags, rewriteParsed, exportToSillyTavern, getParsedList } from '$lib/api';

class ParserStore {
  mode = $state<'default' | 'custom'>('default');
  excludeTags = $state<Set<string>>(new Set());
  allTags = $state<Set<string>>(new Set());
  tagToFiles = $state<Record<string, string[]>>({});
  detectedFiles = $state<string[]>([]);
  loading = $state(false);
  error = $state<string | null>(null);

  get isCustomMode() {
    return this.mode === 'custom';
  }

  get sortedTags(): string[] {
    return [...this.allTags].sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
  }

  getTagState(tag: string): 'include' | 'exclude' {
    const key = tag.toLowerCase();
    if (this.excludeTags.has(key)) return 'exclude';
    return 'include';
  }

  async loadSettings() {
    this.loading = true;
    this.error = null;

    try {
      const settings = await getParserSettings();
      this.mode = settings.mode;
      this.excludeTags = new Set((settings.exclude_tags || []).map(t => t.toLowerCase()));
    } catch (e) {
      this.error = e instanceof Error ? e.message : 'Failed to load settings';
    } finally {
      this.loading = false;
    }
  }

  async save() {
    this.loading = true;
    this.error = null;

    try {
      await saveParserSettings({
        mode: this.mode,
        exclude_tags: [...this.excludeTags],
      });
    } catch (e) {
      this.error = e instanceof Error ? e.message : 'Failed to save settings';
      throw e;
    } finally {
      this.loading = false;
    }
  }

  setMode(mode: 'default' | 'custom') {
    this.mode = mode;
  }

  cycleTagState(tag: string) {
    const key = tag.toLowerCase();
    const newExclude = new Set(this.excludeTags);
    
    if (this.excludeTags.has(key)) {
      newExclude.delete(key);
    } else {
      newExclude.add(key);
    }
    this.excludeTags = newExclude;
  }

  includeAll() {
    this.excludeTags = new Set();
  }

  excludeAll() {
    this.excludeTags = new Set([...this.allTags].map(t => t.toLowerCase()));
  }

  async detectTags(files?: string[]) {
    this.loading = true;
    this.error = null;

    try {
      const data = await getParserTags(files);
      
      const tags = new Set(data.tags.map(t => t.toLowerCase()));
      tags.add('first_message');
      this.allTags = tags;
      
      this.tagToFiles = Object.fromEntries(
        Object.entries(data.by_tag).map(([tag, files]) => [
          tag.toLowerCase(),
          files.map(f => f.toLowerCase())
        ])
      );
      
      this.detectedFiles = data.files.map(n => n.toLowerCase());
      
      return data;
    } catch (e) {
      this.error = e instanceof Error ? e.message : 'Failed to detect tags';
      throw e;
    } finally {
      this.loading = false;
    }
  }

  getFilesForTag(tag: string): string[] {
    return this.tagToFiles[tag.toLowerCase()] || [];
  }

  async rewrite(mode: 'all' | 'latest' | 'custom', files?: string[]) {
    this.loading = true;
    this.error = null;

    try {
      const includeTags = [...this.allTags].filter(t => !this.excludeTags.has(t.toLowerCase()));
      
      const result = await rewriteParsed({
        mode,
        files,
        parser_mode: this.mode,
        include_tags: includeTags,
        exclude_tags: [...this.excludeTags],
      });
      return result;
    } catch (e) {
      this.error = e instanceof Error ? e.message : 'Rewrite failed';
      throw e;
    } finally {
      this.loading = false;
    }
  }

  addTag(tag: string) {
    const key = tag.toLowerCase().trim();
    if (!key) return;
    
    const newTags = new Set(this.allTags);
    newTags.add(key);
    this.allTags = newTags;
  }

  async exportSillyTavernFromTxt(logNames: string[]) {
    this.loading = true;
    this.error = null;

    try {
      const allExports: Array<{name: string; filename: string; json: Record<string, unknown>}> = [];

      for (const logName of logNames) {
        const parsed = await getParsedList(logName);
        if (!parsed.versions || parsed.versions.length === 0) {
          continue;
        }

        // Export only the latest version (first in list, sorted by mtime desc)
        const latestTxt = parsed.versions[0].file;
        const result = await exportToSillyTavern({
          log_name: logName,
          txt_files: [latestTxt],
        });

        allExports.push(...result.exports);
      }

      return { exports: allExports, count: allExports.length };
    } catch (e) {
      this.error = e instanceof Error ? e.message : 'Export failed';
      throw e;
    } finally {
      this.loading = false;
    }
  }
}

export const parserStore = new ParserStore();
