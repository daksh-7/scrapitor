import type {
  LogsResponse,
  ParsedListResponse,
  ParserSettings,
  ParserTagsResponse,
  RewriteResponse,
  DeleteResponse,
  TunnelResponse,
  HealthResponse,
  RenameResponse,
  SillyTavernExportResponse,
} from './types';

class ApiError extends Error {
  constructor(
    message: string,
    public status: number
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

async function request<T>(url: string, options?: RequestInit): Promise<T> {
  const res = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
    },
  });

  if (!res.ok) {
    let message = `HTTP ${res.status}`;
    try {
      const data = await res.json();
      if (data.error) message = data.error;
    } catch {}
    throw new ApiError(message, res.status);
  }

  return res.json();
}

async function getText(url: string): Promise<string> {
  const res = await fetch(url);
  if (!res.ok) {
    throw new ApiError(`HTTP ${res.status}`, res.status);
  }
  return res.text();
}

export async function getLogs(): Promise<LogsResponse> {
  return request<LogsResponse>('/logs');
}

export async function getLogContent(name: string): Promise<string> {
  return getText(`/logs/${encodeURIComponent(name)}`);
}

export async function getParsedList(name: string): Promise<ParsedListResponse> {
  return request<ParsedListResponse>(`/logs/${encodeURIComponent(name)}/parsed`);
}

export async function getParsedContent(logName: string, fileName: string): Promise<string> {
  return getText(`/logs/${encodeURIComponent(logName)}/parsed/${encodeURIComponent(fileName)}`);
}

export async function renameLog(name: string, newName: string): Promise<RenameResponse> {
  return request<RenameResponse>(`/logs/${encodeURIComponent(name)}/rename`, {
    method: 'POST',
    body: JSON.stringify({ new_name: newName }),
  });
}

export async function renameParsedFile(
  logName: string,
  oldFile: string,
  newFile: string
): Promise<RenameResponse> {
  return request<RenameResponse>(`/logs/${encodeURIComponent(logName)}/parsed/rename`, {
    method: 'POST',
    body: JSON.stringify({ old: oldFile, new: newFile }),
  });
}

export async function deleteLogs(files: string[]): Promise<DeleteResponse> {
  return request<DeleteResponse>('/logs/delete', {
    method: 'POST',
    body: JSON.stringify({ files }),
  });
}

export async function deleteParsedFiles(logName: string, files: string[]): Promise<DeleteResponse> {
  return request<DeleteResponse>(`/logs/${encodeURIComponent(logName)}/parsed/delete`, {
    method: 'POST',
    body: JSON.stringify({ files }),
  });
}

export async function getParserSettings(): Promise<ParserSettings> {
  return request<ParserSettings>('/parser-settings');
}

export async function saveParserSettings(settings: Partial<ParserSettings>): Promise<ParserSettings> {
  return request<ParserSettings>('/parser-settings', {
    method: 'POST',
    body: JSON.stringify(settings),
  });
}

export async function getParserTags(files?: string[]): Promise<ParserTagsResponse> {
  const params = new URLSearchParams();
  if (files?.length) {
    files.forEach((f) => params.append('file', f));
  } else {
    params.set('mode', 'latest');
  }
  return request<ParserTagsResponse>(`/parser-tags?${params}`);
}

export async function rewriteParsed(options: {
  mode: 'all' | 'latest' | 'custom';
  files?: string[];
  parser_mode?: 'default' | 'custom';
  include_tags?: string[];
  exclude_tags?: string[];
}): Promise<RewriteResponse> {
  return request<RewriteResponse>('/parser-rewrite', {
    method: 'POST',
    body: JSON.stringify(options),
  });
}

export async function exportToSillyTavern(options: {
  log_name: string;
  txt_files: string[];
}): Promise<SillyTavernExportResponse> {
  return request<SillyTavernExportResponse>('/export-sillytavern', {
    method: 'POST',
    body: JSON.stringify(options),
  });
}

export async function getTunnel(): Promise<TunnelResponse> {
  return request<TunnelResponse>('/tunnel');
}

export async function getHealth(): Promise<HealthResponse> {
  return request<HealthResponse>('/health');
}

export type { ApiError };
export * from './types';

