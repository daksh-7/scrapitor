// API response types matching Flask endpoints

export interface LogItem {
  name: string;
  mtime: number;
  size: number;
}

export interface LogsResponse {
  logs: string[];
  items: LogItem[];
  total: number;
  total_all: number;
  parsed_total: number;
  recent: string[];
}

export interface ParsedVersion {
  id: string;
  file: string;
  size: number;
  mtime: number;
  version: number | null;
}

export interface ParsedListResponse {
  versions: ParsedVersion[];
  latest: string;
  dir?: string;
  error?: string;
}

export interface ParserSettings {
  mode: 'default' | 'custom';
  include_tags: string[];
  exclude_tags: string[];
}

export interface ParserTagsResponse {
  tags: string[];
  files: string[];
  by_file: Record<string, string[]>;
  by_tag: Record<string, string[]>;
}

export interface RewriteResult {
  file: string;
  ok: boolean;
  stdout?: string;
  stderr?: string;
  error?: string;
}

export interface RewriteResponse {
  rewritten: number;
  results: RewriteResult[];
}

export interface DeleteResult {
  file: string;
  ok: boolean;
  error?: string;
}

export interface DeleteResponse {
  deleted: number;
  results: DeleteResult[];
  error?: string;
}

export interface TunnelResponse {
  url: string;
}

export interface HealthResponse {
  status: string;
  uptime_seconds: number;
  version: string;
  config: {
    port: number;
  };
}

export interface RenameResponse {
  old: string;
  new: string;
}

export interface SillyTavernExport {
  name: string;
  filename: string;
  source_txt?: string;
  json: Record<string, unknown>;
}

export interface SillyTavernExportResponse {
  exports: SillyTavernExport[];
  count: number;
  error?: string;
}

