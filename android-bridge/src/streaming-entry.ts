/**
 * Android 端流媒体 bundle 入口。
 * 直接复用 SPlayer-Next 主进程的 streaming 服务层（config/connection/library/
 * sync/favorites/snapshot + subsonic/jellyfin adapters），
 * 通过 stub 将 electron 专属依赖替换为浏览器等价实现。
 * 暴露 globalThis.StreamingBridge.handle(method, args)，与 preload 的 streaming.* 契约一致。
 */
import {
  addStreamingServer,
  getStreamingConfig,
  getStreamingServer,
  removeStreamingServer,
  setActiveStreamingServer,
  updateStreamingServer,
} from "@main/services/streaming/config";
import {
  connectStreamingServer,
  testStreamingConnection,
  withStreamingAdapter,
} from "@main/services/streaming/connection";
import {
  deleteLibraryByServer,
  getLibrarySnapshot,
  searchLibrary,
} from "@main/services/streaming/library";
import { requestStreamingFavorite } from "@main/services/streaming/favorites";
import { cancelStreamingSync, queueStreamingSync } from "@main/services/streaming/sync";
import { invalidateStreamingSession } from "@main/services/streaming/adapters/resolve";
import { isDbOpen } from "@main/database";
import type { StreamingServerInput } from "@shared/types/streaming";

/** 原生桥调用（由 bridge.js 注入），用于切换服务器时停止原生播放 */
type NativeCall = (ns: string, method: string, args: unknown[]) => Promise<unknown>;
let nativeCall: NativeCall | null = null;

/** 对应 ipc/player.ts 的 stopStreamingPlayer：Android 端转发给原生播放引擎 */
const stopStreamingPlayer = async (serverId: string): Promise<void> => {
  try {
    await nativeCall?.("player", "stop", [serverId]);
  } catch {
    // 原生桥未就绪时忽略（无播放进行中）
  }
};

/** 复刻 electron/main/ipc/streaming.ts 的全部 handler 语义 */
const handlers: Record<string, (...args: any[]) => unknown> = {
  loadServers: () => getStreamingConfig(),
  addServer: (input: StreamingServerInput) => addStreamingServer(input),
  updateServer: async (serverId: string, input: StreamingServerInput) => {
    const previous = getStreamingConfig().servers.find((server) => server.id === serverId);
    const identityChanged =
      previous?.type !== input.type ||
      previous?.url !== input.url.trim().replace(/\/+$/, "") ||
      previous?.username !== input.username ||
      Boolean(input.password);
    if (!identityChanged) return updateStreamingServer(serverId, input);
    cancelStreamingSync(serverId);
    await stopStreamingPlayer(serverId);
    const updated = await updateStreamingServer(serverId, input);
    invalidateStreamingSession(serverId);
    cancelStreamingSync(serverId);
    if (identityChanged && isDbOpen()) deleteLibraryByServer(serverId);
    return updated;
  },
  removeServer: async (serverId: string) => {
    cancelStreamingSync(serverId);
    await stopStreamingPlayer(serverId);
    invalidateStreamingSession(serverId);
    cancelStreamingSync(serverId);
    removeStreamingServer(serverId);
    if (isDbOpen()) deleteLibraryByServer(serverId);
    return null;
  },
  setActiveServer: (serverId: string | null) => setActiveStreamingServer(serverId),
  testConnection: (input: StreamingServerInput, serverId?: string) =>
    testStreamingConnection(input, serverId),
  connect: (serverId: string) => connectStreamingServer(serverId),
  disconnect: async (serverId: string) => {
    cancelStreamingSync(serverId);
    await stopStreamingPlayer(serverId);
    invalidateStreamingSession(serverId);
    return null;
  },
  getFavorite: (serverId: string, trackId: string) =>
    requestStreamingFavorite(serverId, trackId),
  setFavorite: (serverId: string, trackId: string, value: boolean) =>
    requestStreamingFavorite(serverId, trackId, value),
  getSnapshot: (serverId: string) => getLibrarySnapshot(serverId),
  sync: async (serverId: string, force = false) =>
    queueStreamingSync(await getStreamingServer(serverId), force),
  search: (serverId: string, query: string) => searchLibrary(serverId, String(query ?? "").slice(0, 200)),
  getAlbumSongs: (serverId: string, albumId: string) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getAlbumSongs(config, albumId)),
  getPlaylistSongs: (serverId: string, playlistId: string) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getPlaylistSongs(config, playlistId)),
  getArtistAlbums: (serverId: string, artistId: string) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getArtistAlbums(config, artistId)),
  getArtistSongs: (serverId: string, artistId: string) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getArtistSongs(config, artistId)),
  getLyrics: (
    serverId: string,
    trackId: string,
    hint?: { artist?: string; title?: string },
  ) => withStreamingAdapter(serverId, (config, adapter) => adapter.getLyrics(config, trackId, hint)),
};

interface StreamingApi {
  /** 注入原生桥调用器（bridge.js 加载本 bundle 后调用） */
  setNativeCall: (fn: NativeCall | null) => void;
  /** 统一分发入口：method 对应 preload 的 streaming.* 方法名 */
  handle: (method: string, args: unknown[]) => Promise<unknown>;
}

const api: StreamingApi = {
  setNativeCall: (fn) => {
    nativeCall = fn;
  },
  handle: async (method, args) => {
    const handler = handlers[method];
    if (!handler) {
      throw new Error(`streaming.${method} 暂未在 Android 端实现`);
    }
    return handler(...(args ?? []));
  },
};

(globalThis as unknown as { StreamingBridge: StreamingApi }).StreamingBridge = api;

console.info("[streaming-bundle] ready");