/**
 * Android 本地媒体库：复刻 electron/main/database/streaming/* 的查询语义。
 *
 * 存储布局（localStorage）：
 * - splayer:streaming.v1.lib.<serverId>.<kind>.<i>  每块最多 200 条 [remoteId, data, generation]
 * - splayer:streaming.v1.lib.<serverId>.index       最后写入，作为原子发布标记
 * - splayer:streaming.v1.fav.<serverId>             收藏覆盖层
 *
 * 单服务器容量约 3.5MB；超限先剥离 coverOriginal，再截断并标记 truncated。
 * 写入触发 QuotaExceeded 时降级为纯内存并通过 streaming:syncState 推送警告。
 */
import type { Track } from "@shared/types/player";

const CHUNK_SIZE = 200;
const MAX_SERVER_BYTES = 3.5 * 1024 * 1024;
const LIB_PREFIX = "splayer:streaming.v1.lib.";
const FAV_PREFIX = "splayer:streaming.v1.fav.";

type Kind = "tracks" | "albums" | "artists" | "playlists";
const KINDS: Kind[] = ["tracks", "albums", "artists", "playlists"];

interface Row {
  data: string;
  generation: number;
}

interface ServerState {
  kinds: Record<Kind, Map<string, Row>>;
  favorites: Map<string, boolean>;
  memoryOnly: boolean;
  truncated: boolean;
  warned: Set<string>;
}

interface LibraryIndex {
  version?: number;
  kinds?: Record<string, { chunks?: number; count?: number }>;
  truncated?: boolean;
}

const servers = new Map<string, ServerState>();
const batches = new Set<string>();

const storage = (): Storage | null => {
  try {
    return (globalThis as { localStorage?: Storage }).localStorage ?? null;
  } catch {
    return null;
  }
};

const indexKey = (serverId: string): string => `${LIB_PREFIX}${serverId}.index`;
const chunkKey = (serverId: string, kind: Kind, index: number): string =>
  `${LIB_PREFIX}${serverId}.${kind}.${index}`;
const favoriteKey = (serverId: string): string => `${FAV_PREFIX}${serverId}`;

const createState = (): ServerState => ({
  kinds: {
    tracks: new Map(),
    albums: new Map(),
    artists: new Map(),
    playlists: new Map(),
  },
  favorites: new Map(),
  memoryOnly: false,
  truncated: false,
  warned: new Set(),
});

const readIndex = (serverId: string): LibraryIndex | null => {
  const raw = storage()?.getItem(indexKey(serverId));
  if (!raw) return null;
  try {
    return JSON.parse(raw) as LibraryIndex;
  } catch {
    return null;
  }
};

const applyFavorite = (state: ServerState, remoteId: string, favorite: boolean): void => {
  const row = state.kinds.tracks.get(remoteId);
  if (!row) return;
  try {
    const entity = JSON.parse(row.data) as Record<string, unknown>;
    entity.favorite = favorite;
    row.data = JSON.stringify(entity);
  } catch {
    // 损坏条目忽略
  }
};

const loadState = (serverId: string, state: ServerState): void => {
  const ls = storage();
  if (!ls) {
    state.memoryOnly = true;
    return;
  }
  const favorites = ls.getItem(favoriteKey(serverId));
  if (favorites) {
    try {
      const parsed = JSON.parse(favorites) as Record<string, boolean>;
      for (const [remoteId, favorite] of Object.entries(parsed)) {
        state.favorites.set(remoteId, Boolean(favorite));
      }
    } catch {
      // 收藏覆盖层损坏时忽略
    }
  }
  const index = readIndex(serverId);
  if (!index?.kinds) {
    for (const [remoteId, favorite] of state.favorites) applyFavorite(state, remoteId, favorite);
    return;
  }
  for (const kind of KINDS) {
    const info = index.kinds[kind];
    const chunks = Number(info?.chunks ?? 0);
    const target = state.kinds[kind];
    for (let i = 0; i < chunks; i++) {
      const raw = ls.getItem(chunkKey(serverId, kind, i));
      if (!raw) continue;
      try {
        const entries = JSON.parse(raw) as [string, string, number][];
        for (const entry of entries) {
          if (!Array.isArray(entry) || entry.length < 2) continue;
          target.set(String(entry[0]), {
            data: String(entry[1]),
            generation: Number(entry[2]) || 0,
          });
        }
      } catch {
        // 单个分块损坏时跳过，保持其余数据可用
      }
    }
  }
  state.truncated = Boolean(index.truncated);
  for (const [remoteId, favorite] of state.favorites) applyFavorite(state, remoteId, favorite);
};

const getState = (serverId: string): ServerState => {
  let state = servers.get(serverId);
  if (!state) {
    state = createState();
    loadState(serverId, state);
    servers.set(serverId, state);
  }
  return state;
};

const utf8Length = (text: string): number => {
  if (typeof TextEncoder !== "undefined") return new TextEncoder().encode(text).length;
  return text.length * 2;
};

const buildChunks = (
  state: ServerState,
): { chunks: Record<Kind, string[]>; bytes: number } => {
  const chunks = {} as Record<Kind, string[]>;
  let bytes = 0;
  for (const kind of KINDS) {
    const entries: [string, string, number][] = [];
    for (const [remoteId, row] of state.kinds[kind]) {
      entries.push([remoteId, row.data, row.generation]);
    }
    const list: string[] = [];
    for (let i = 0; i < entries.length; i += CHUNK_SIZE) {
      const serialized = JSON.stringify(entries.slice(i, i + CHUNK_SIZE));
      list.push(serialized);
      bytes += utf8Length(serialized);
    }
    chunks[kind] = list;
  }
  if (state.favorites.size) bytes += utf8Length(JSON.stringify(Object.fromEntries(state.favorites)));
  return { chunks, bytes };
};

const stripCoverOriginal = (state: ServerState): void => {
  for (const row of state.kinds.tracks.values()) {
    try {
      const entity = JSON.parse(row.data) as Record<string, unknown>;
      if (entity && typeof entity === "object" && "coverOriginal" in entity) {
        delete entity.coverOriginal;
        row.data = JSON.stringify(entity);
      }
    } catch {
      // 忽略损坏条目
    }
  }
};

const notify = (state: ServerState, serverId: string, key: string, message: string): void => {
  if (state.warned.has(key)) return;
  state.warned.add(key);
  console.warn(`[streaming-db] ${message}`);
  try {
    const dispatch = (globalThis as {
      __splayerDispatch?: (channel: string, payload: unknown) => void;
    }).__splayerDispatch;
    dispatch?.("streaming:syncState", {
      serverId,
      state: "running",
      warning: message,
    });
  } catch {
    // 桥未就绪时忽略
  }
};

const isQuotaError = (error: unknown): boolean => {
  const name = (error as { name?: string })?.name;
  const code = (error as { code?: number })?.code;
  return name === "QuotaExceededError" || name === "NS_ERROR_DOM_QUOTA_REACHED" || code === 22;
};

const persistState = (serverId: string, state: ServerState): void => {
  if (state.memoryOnly) return;
  const ls = storage();
  if (!ls) {
    state.memoryOnly = true;
    return;
  }

  let built = buildChunks(state);
  if (built.bytes > MAX_SERVER_BYTES) {
    stripCoverOriginal(state);
    built = buildChunks(state);
  }
  if (built.bytes > MAX_SERVER_BYTES) {
    state.truncated = true;
    for (const kind of KINDS) {
      while (built.bytes > MAX_SERVER_BYTES && state.kinds[kind].size > 0) {
        const ids = [...state.kinds[kind].keys()];
        const remove = Math.max(1, Math.floor(ids.length * 0.1));
        for (let i = 0; i < remove && ids.length - 1 - i >= 0; i++) {
          state.kinds[kind].delete(ids[ids.length - 1 - i]);
        }
        built = buildChunks(state);
      }
      if (built.bytes <= MAX_SERVER_BYTES) break;
    }
    notify(state, serverId, "truncated", "媒体库超过本地容量上限，已截断部分数据");
  }

  const previous = readIndex(serverId);
  try {
    for (const kind of KINDS) {
      const list = built.chunks[kind];
      for (let i = 0; i < list.length; i++) ls.setItem(chunkKey(serverId, kind, i), list[i]);
      const stale = Number(previous?.kinds?.[kind]?.chunks ?? 0);
      for (let i = list.length; i < stale; i++) ls.removeItem(chunkKey(serverId, kind, i));
    }
    if (state.favorites.size)
      ls.setItem(favoriteKey(serverId), JSON.stringify(Object.fromEntries(state.favorites)));
    else ls.removeItem(favoriteKey(serverId));
    const index: LibraryIndex = {
      version: 1,
      kinds: Object.fromEntries(
        KINDS.map((kind) => [kind, { chunks: built.chunks[kind].length, count: state.kinds[kind].size }]),
      ),
      truncated: state.truncated,
    };
    // 索引最后写入：即使中途失败，读取方仍看到上一版索引
    ls.setItem(indexKey(serverId), JSON.stringify(index));
  } catch (error) {
    // 任一写入失败都移除索引，避免读取方看到新旧混合的分块
    try {
      ls.removeItem(indexKey(serverId));
    } catch {
      // 忽略
    }
    if (isQuotaError(error)) {
      state.memoryOnly = true;
      notify(state, serverId, "quota", "localStorage 配额不足，媒体库仅保存在内存中");
      return;
    }
    console.warn("[streaming-db] 持久化失败", error);
  }
};

const persist = (serverId: string): void => {
  if (batches.has(serverId)) return;
  persistState(serverId, getState(serverId));
};

/** 同步发布期间合并写入，避免每页都重写全部分块 */
export const beginStreamingLibraryBatch = (serverId: string): void => {
  batches.add(serverId);
};

/** 结束批量写入并立即落盘 */
export const endStreamingLibraryBatch = (serverId: string): void => {
  batches.delete(serverId);
  persistState(serverId, getState(serverId));
};

const clearPersisted = (serverId: string): void => {
  const ls = storage();
  if (!ls) return;
  const prefix = `${LIB_PREFIX}${serverId}.`;
  const keys: string[] = [];
  for (let i = 0; i < ls.length; i++) {
    const key = ls.key(i);
    if (key?.startsWith(prefix)) keys.push(key);
  }
  for (const key of keys) ls.removeItem(key);
  ls.removeItem(favoriteKey(serverId));
};

const groupRecords = <T extends { serverId: string }>(records: T[]): Map<string, T[]> => {
  const grouped = new Map<string, T[]>();
  for (const record of records) {
    const list = grouped.get(record.serverId);
    if (list) list.push(record);
    else grouped.set(record.serverId, [record]);
  }
  return grouped;
};

const parseEntity = <T>(row: Row): T => JSON.parse(row.data) as T;

const sortedEntities = <T>(state: ServerState, kind: Kind, nameOf: (entity: T) => string): T[] => {
  const rows: { id: string; name: string; entity: T }[] = [];
  for (const [id, row] of state.kinds[kind]) {
    const entity = parseEntity<T>(row);
    rows.push({ id, name: String(nameOf(entity) ?? "").toLowerCase(), entity });
  }
  rows.sort((a, b) => {
    if (a.name !== b.name) return a.name < b.name ? -1 : 1;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return rows.map((item) => item.entity);
};

// MARK: - @main/database 主接口

/** 业务层只依赖 isDbOpen；SQL 接口由本文件的其他导出替代 */
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
  const state = getState(serverId);
  state.favorites.set(remoteId, favorite);
  applyFavorite(state, remoteId, favorite);
  persist(serverId);
};

export const upsertTracks = (records: StreamingTrackRecord[]): void => {
  if (records.length === 0) return;
  for (const [serverId, group] of groupRecords(records)) {
    const state = getState(serverId);
    for (const record of group) {
      state.kinds.tracks.set(record.remoteId, {
        data: JSON.stringify(record.track),
        generation: record.generation,
      });
    }
    persist(serverId);
  }
};

export const getTracks = (serverId: string): Track[] =>
  sortedEntities<Track>(getState(serverId), "tracks", (track) => track.title);

export const searchTracks = (serverId: string, query: string): Track[] => {
  const needle = query.trim().toLowerCase();
  if (!needle) return [];
  const state = getState(serverId);
  const rows: { id: string; title: string; track: Track }[] = [];
  for (const [id, row] of state.kinds.tracks) {
    const track = parseEntity<Track>(row);
    const haystack = [track.title, track.album?.name, ...track.artists.map((artist) => artist.name)]
      .filter(Boolean)
      .join("\n")
      .toLowerCase();
    if (haystack.includes(needle)) rows.push({ id, title: track.title.toLowerCase(), track });
  }
  rows.sort((a, b) => {
    if (a.title !== b.title) return a.title < b.title ? -1 : 1;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return rows.map((item) => item.track);
};

export const deleteStaleTracks = (serverId: string, generation: number): void => {
  const state = getState(serverId);
  for (const [remoteId, row] of state.kinds.tracks) {
    if (row.generation !== generation) state.kinds.tracks.delete(remoteId);
  }
  persist(serverId);
};

export const deleteTracksByServer = (serverId: string): void => {
  const state = getState(serverId);
  state.kinds.tracks.clear();
  state.favorites.clear();
  persist(serverId);
};

// MARK: - remote_albums

export interface StreamingAlbumRecord {
  serverId: string;
  remoteId: string;
  album: Record<string, unknown>;
  generation: number;
}

export const upsertAlbums = (records: StreamingAlbumRecord[]): void => {
  if (records.length === 0) return;
  for (const [serverId, group] of groupRecords(records)) {
    const state = getState(serverId);
    for (const record of group) {
      state.kinds.albums.set(record.remoteId, {
        data: JSON.stringify(record.album),
        generation: record.generation,
      });
    }
    persist(serverId);
  }
};

export const getAlbums = (serverId: string): Record<string, unknown>[] =>
  sortedEntities<Record<string, unknown>>(getState(serverId), "albums", (album) =>
    String(album?.name ?? ""),
  );

export const deleteStaleAlbums = (serverId: string, generation: number): void => {
  const state = getState(serverId);
  for (const [remoteId, row] of state.kinds.albums) {
    if (row.generation !== generation) state.kinds.albums.delete(remoteId);
  }
  persist(serverId);
};

export const deleteAlbumsByServer = (serverId: string): void => {
  getState(serverId).kinds.albums.clear();
  persist(serverId);
};

// MARK: - remote_artists

export interface StreamingArtistRecord {
  serverId: string;
  remoteId: string;
  artist: Record<string, unknown>;
  generation: number;
}

export const upsertArtists = (records: StreamingArtistRecord[]): void => {
  if (records.length === 0) return;
  for (const [serverId, group] of groupRecords(records)) {
    const state = getState(serverId);
    for (const record of group) {
      state.kinds.artists.set(record.remoteId, {
        data: JSON.stringify(record.artist),
        generation: record.generation,
      });
    }
    persist(serverId);
  }
};

export const getArtists = (serverId: string): Record<string, unknown>[] =>
  sortedEntities<Record<string, unknown>>(getState(serverId), "artists", (artist) =>
    String(artist?.name ?? ""),
  );

export const deleteStaleArtists = (serverId: string, generation: number): void => {
  const state = getState(serverId);
  for (const [remoteId, row] of state.kinds.artists) {
    if (row.generation !== generation) state.kinds.artists.delete(remoteId);
  }
  persist(serverId);
};

export const deleteArtistsByServer = (serverId: string): void => {
  getState(serverId).kinds.artists.clear();
  persist(serverId);
};

// MARK: - remote_playlists

export interface StreamingPlaylistRecord {
  serverId: string;
  remoteId: string;
  playlist: Record<string, unknown>;
  generation: number;
}

export const upsertPlaylists = (records: StreamingPlaylistRecord[]): void => {
  if (records.length === 0) return;
  for (const [serverId, group] of groupRecords(records)) {
    const state = getState(serverId);
    for (const record of group) {
      state.kinds.playlists.set(record.remoteId, {
        data: JSON.stringify(record.playlist),
        generation: record.generation,
      });
    }
    persist(serverId);
  }
};

export const getPlaylists = (serverId: string): Record<string, unknown>[] =>
  sortedEntities<Record<string, unknown>>(getState(serverId), "playlists", (playlist) =>
    String(playlist?.name ?? ""),
  );

export const deleteStalePlaylists = (serverId: string, generation: number): void => {
  const state = getState(serverId);
  for (const [remoteId, row] of state.kinds.playlists) {
    if (row.generation !== generation) state.kinds.playlists.delete(remoteId);
  }
  persist(serverId);
};

export const deletePlaylistsByServer = (serverId: string): void => {
  getState(serverId).kinds.playlists.clear();
  persist(serverId);
};

// MARK: - 内部辅助（snapshot 使用）

/** 读取当前四个集合的最大代次，用于生成新快照代次 */
export const getStreamingMaxGeneration = (serverId: string): number => {
  const state = getState(serverId);
  let max = 0;
  for (const kind of KINDS) {
    for (const row of state.kinds[kind].values()) max = Math.max(max, row.generation);
  }
  return max;
};

/** 彻底删除服务器的本地库与收藏覆盖层 */
export const deleteStreamingLibraryByServer = (serverId: string): void => {
  const state = servers.get(serverId);
  if (state) {
    for (const kind of KINDS) state.kinds[kind].clear();
    state.favorites.clear();
  }
  servers.delete(serverId);
  batches.delete(serverId);
  clearPersisted(serverId);
};
