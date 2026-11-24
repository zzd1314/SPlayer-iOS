/**
 * Android 端数据库 stub：以内存 Map + localStorage 持久化替代 better-sqlite3。
 * 导出接口与 electron/main/database 下的同名模块保持一致，
 * 供 esbuild 通过 alias 将 @main/database 及其子模块路由到本文件。
 */
import type { Track } from "@shared/types/player";

// MARK: - localStorage 工具（WebView 环境必有）

const readStore = (): Record<string, unknown> => {
  try {
    return JSON.parse(localStorage.getItem("splayer:streaming-db") || "{}") as Record<string, unknown>;
  } catch {
    return {};
  }
};

const writeStore = (data: Record<string, unknown>): void => {
  try {
    localStorage.setItem("splayer:streaming-db", JSON.stringify(data));
  } catch {
    // 存储满时静默失败，与原库行为差异记录于发布说明
  }
};

interface RecordRow {
  serverId: string;
  remoteId: string;
  data: string; // JSON 序列化的实体
  name: string;
  searchText: string;
  generation: number;
  updatedAt: number;
}

// MARK: - 通用表操作

class MemTable {
  rows: RecordRow[] = [];

  upsert(row: RecordRow): void {
    const idx = this.rows.findIndex(
      (r) => r.serverId === row.serverId && r.remoteId === row.remoteId,
    );
    if (idx >= 0) this.rows[idx] = row;
    else this.rows.push(row);
  }

  list(serverId: string): RecordRow[] {
    return this.rows
      .filter((r) => r.serverId === serverId)
      .sort((a, b) => a.name.localeCompare(b.name) || a.remoteId.localeCompare(b.remoteId));
  }

  search(serverId: string, query: string): RecordRow[] {
    const q = query.trim().toLowerCase();
    if (!q) return [];
    return this.list(serverId).filter((r) => r.searchText.toLowerCase().includes(q));
  }

  deleteStale(serverId: string, generation: number): void {
    this.rows = this.rows.filter(
      (r) => r.serverId !== serverId || r.generation === generation,
    );
  }

  deleteByServer(serverId: string): void {
    this.rows = this.rows.filter((r) => r.serverId !== serverId);
  }

  setFavorite(serverId: string, remoteId: string, favorite: boolean): void {
    const row = this.rows.find(
      (r) => r.serverId === serverId && r.remoteId === remoteId,
    );
    if (row) {
      try {
        const entity = JSON.parse(row.data) as Record<string, unknown>;
        entity.favorite = favorite;
        row.data = JSON.stringify(entity);
      } catch {
        // 数据损坏时忽略
      }
    }
  }
}

interface DbState {
  tracks: MemTable;
  albums: MemTable;
  artists: MemTable;
  playlists: MemTable;
}

let dbState: DbState | null = null;

const state = (): DbState => {
  if (!dbState) {
    const saved = readStore();
    const revive = (key: string): MemTable => {
      const t = new MemTable();
      const rows = saved[key] as RecordRow[] | undefined;
      if (Array.isArray(rows)) t.rows = rows;
      return t;
    };
    dbState = {
      tracks: revive("tracks"),
      albums: revive("albums"),
      artists: revive("artists"),
      playlists: revive("playlists"),
    };
  }
  return dbState;
};

const persist = (): void => {
  const s = state();
  writeStore({
    tracks: s.tracks.rows,
    albums: s.albums.rows,
    artists: s.artists.rows,
    playlists: s.playlists.rows,
  });
};

const buildRow = (
  serverId: string,
  remoteId: string,
  entity: unknown,
  name: string,
  searchTextExtra: string[],
  generation: number,
): RecordRow => ({
  serverId,
  remoteId,
  data: JSON.stringify(entity),
  name,
  searchText: [name, ...searchTextExtra].filter(Boolean).join("\n"),
  generation,
  updatedAt: Date.now(),
});

// MARK: - @main/database 主接口

/** 原版使用 better-sqlite3；Android 端业务不直接触达 SQL，返回最小 mock */
export const getDb = (): unknown => ({
  prepare: () => ({ run: () => {}, all: () => [], get: () => undefined }),
  exec: () => {},
  pragma: () => [],
  transaction: <T>(fn: () => T) => (): T => fn(),
});

export const isDbOpen = (): boolean => true;
export const initDatabase = (): void => {};
export const closeDatabase = (): void => {};

// MARK: - remote_tracks

export interface StreamingTrackRecord {
  serverId: string;
  remoteId: string;
  track: Track;
  generation: number;
}

export const updateStreamingFavorite = (
  serverId: string,
  remoteId: string,
  favorite: boolean,
): void => {
  state().tracks.setFavorite(serverId, remoteId, favorite);
  persist();
};

export const upsertTracks = (records: StreamingTrackRecord[]): void => {
  if (records.length === 0) return;
  for (const record of records) {
    state().tracks.upsert(
      buildRow(
        record.serverId,
        record.remoteId,
        record.track,
        record.track.title,
        [record.track.album?.name, ...record.track.artists.map((a) => a.name)],
        record.generation,
      ),
    );
  }
  persist();
};

export const getTracks = (serverId: string): Track[] =>
  state()
    .tracks.list(serverId)
    .map((row) => JSON.parse(row.data) as Track);

export const searchTracks = (serverId: string, query: string): Track[] =>
  state()
    .tracks.search(serverId, query)
    .map((row) => JSON.parse(row.data) as Track);

export const deleteStaleTracks = (serverId: string, generation: number): void => {
  state().tracks.deleteStale(serverId, generation);
  persist();
};

export const deleteTracksByServer = (serverId: string): void => {
  state().tracks.deleteByServer(serverId);
  persist();
};

// MARK: - remote_albums

export interface StreamingAlbumRecord {
  serverId: string;
  remoteId: string;
  album: Record<string, unknown>;
  generation: number;
}

const albumName = (album: unknown): string =>
  String((album as { name?: string })?.name ?? "");

export const upsertAlbums = (records: StreamingAlbumRecord[]): void => {
  for (const record of records) {
    state().albums.upsert(
      buildRow(record.serverId, record.remoteId, record.album, albumName(record.album), [], record.generation),
    );
  }
  persist();
};

export const getAlbums = (serverId: string): Record<string, unknown>[] =>
  state()
    .albums.list(serverId)
    .map((row) => JSON.parse(row.data) as Record<string, unknown>);

export const deleteStaleAlbums = (serverId: string, generation: number): void => {
  state().albums.deleteStale(serverId, generation);
  persist();
};

export const deleteAlbumsByServer = (serverId: string): void => {
  state().albums.deleteByServer(serverId);
  persist();
};

// MARK: - remote_artists

export interface StreamingArtistRecord {
  serverId: string;
  remoteId: string;
  artist: Record<string, unknown>;
  generation: number;
}

export const upsertArtists = (records: StreamingArtistRecord[]): void => {
  for (const record of records) {
    state().artists.upsert(
      buildRow(record.serverId, record.remoteId, record.artist, albumName(record.artist), [], record.generation),
    );
  }
  persist();
};

export const getArtists = (serverId: string): Record<string, unknown>[] =>
  state()
    .artists.list(serverId)
    .map((row) => JSON.parse(row.data) as Record<string, unknown>);

export const deleteStaleArtists = (serverId: string, generation: number): void => {
  state().artists.deleteStale(serverId, generation);
  persist();
};

export const deleteArtistsByServer = (serverId: string): void => {
  state().artists.deleteByServer(serverId);
  persist();
};

// MARK: - remote_playlists

export interface StreamingPlaylistRecord {
  serverId: string;
  remoteId: string;
  playlist: Record<string, unknown>;
  generation: number;
}

export const upsertPlaylists = (records: StreamingPlaylistRecord[]): void => {
  for (const record of records) {
    state().playlists.upsert(
      buildRow(record.serverId, record.remoteId, record.playlist, albumName(record.playlist), [], record.generation),
    );
  }
  persist();
};

export const getPlaylists = (serverId: string): Record<string, unknown>[] =>
  state()
    .playlists.list(serverId)
    .map((row) => JSON.parse(row.data) as Record<string, unknown>);

export const deleteStalePlaylists = (serverId: string, generation: number): void => {
  state().playlists.deleteStale(serverId, generation);
  persist();
};

export const deletePlaylistsByServer = (serverId: string): void => {
  state().playlists.deleteByServer(serverId);
  persist();
};