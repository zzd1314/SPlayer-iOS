/**
 * Android 端流媒体 bundle 入口。
 * 复用 SPlayer-Next 主进程 streaming 服务层（config/connection/library/sync/favorites/
 * snapshot + subsonic/jellyfin adapters），通过 stub 与网络垫片适配 WebView。
 * 暴露 window.StreamingBridge，契约与 bridge.js 保持一致。
 */
import "./boot";
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
import { deleteStreamingLibraryByServer } from "./stubs/db";
import { beginStreamingPlayback, onPlayerEvent, stopStreamingPlayback } from "./playback";
import { parseStreamingSource } from "@shared/utils/streamingSource";
import type { StreamingServerInput } from "@shared/types/streaming";

/** 原生桥调用（由 bridge.js 注入），Android 端当前不需要主动调用原生 */
type NativeCall = (ns: string, method: string, args: unknown[]) => Promise<unknown>;
let nativeCall: NativeCall | null = null;

/** 复刻 electron/main/ipc/streaming.ts 的 handler 语义（去掉桌面播放器调用） */
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
    const updated = await updateStreamingServer(serverId, input);
    invalidateStreamingSession(serverId);
    cancelStreamingSync(serverId);
    // Android 没有独立播放进程，直接清空本地媒体库
    deleteLibraryByServer(serverId);
    deleteStreamingLibraryByServer(serverId);
    return updated;
  },
  removeServer: async (serverId: string) => {
    cancelStreamingSync(serverId);
    invalidateStreamingSession(serverId);
    cancelStreamingSync(serverId);
    removeStreamingServer(serverId);
    deleteLibraryByServer(serverId);
    deleteStreamingLibraryByServer(serverId);
  },
  setActiveServer: (serverId: string | null) => setActiveStreamingServer(serverId),
  testConnection: (input: StreamingServerInput, serverId?: string) =>
    testStreamingConnection(input, serverId),
  connect: (serverId: string) => connectStreamingServer(serverId),
  disconnect: async (serverId: string) => {
    cancelStreamingSync(serverId);
    invalidateStreamingSession(serverId);
  },
  getFavorite: (serverId: string, trackId: string) => requestStreamingFavorite(serverId, trackId),
  setFavorite: (serverId: string, trackId: string, value: boolean) =>
    requestStreamingFavorite(serverId, trackId, value),
  getSnapshot: (serverId: string) => getLibrarySnapshot(serverId),
  sync: async (serverId: string, force = false) =>
    queueStreamingSync(await getStreamingServer(serverId), force),
  search: (serverId: string, query: string) =>
    searchLibrary(serverId, String(query ?? "").slice(0, 200)),
  getAlbumSongs: (serverId: string, albumId: string) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getAlbumSongs(config, albumId)),
  getPlaylistSongs: (serverId: string, playlistId: string) =>
    withStreamingAdapter(serverId, (config, adapter) =>
      adapter.getPlaylistSongs(config, playlistId),
    ),
  getArtistAlbums: (serverId: string, artistId: string) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getArtistAlbums(config, artistId)),
  getArtistSongs: (serverId: string, artistId: string) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getArtistSongs(config, artistId)),
  getLyrics: (serverId: string, trackId: string, hint?: { artist?: string; title?: string }) =>
    withStreamingAdapter(serverId, (config, adapter) => adapter.getLyrics(config, trackId, hint)),
};

/** 为 Jellyfin/Emby 附带 Authorization，Subsonic 鉴权全在 URL 查询参数里 */
const playbackHeaders = (
  config: { type: string; id: string; accessToken?: string },
): Record<string, string> | undefined => {
  if ((config.type !== "jellyfin" && config.type !== "emby") || !config.accessToken) return undefined;
  const header = config.type === "emby" ? "X-Emby-Authorization" : "Authorization";
  return {
    [header]: `MediaBrowser Client="SPlayer-Next", Device="SPlayer Android", DeviceId="splayer-next-${config.id}", Version="1.0.0", Token="${config.accessToken}"`,
  };
};

/**
 * 把 streaming:// 占位符解析为带鉴权的真实播放地址
 * @param streamingUrl - 渲染层生成的音源身份
 * @param options - playback 为 true 时同步绑定播放上报会话（仅真正的播放加载传）
 * @returns 真实地址、可选请求头与会话 ID
 */
const resolveSource = async (
  streamingUrl: string,
  options?: { playback?: boolean },
): Promise<{ url: string; headers?: Record<string, string>; sessionId: string }> => {
  const { serverId, trackId, serverRevision } = parseStreamingSource(streamingUrl);
  const sessionId =
    typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return withStreamingAdapter(serverId, async (config, adapter) => {
    if ((config.mediaRevision ?? 0) !== serverRevision)
      throw new Error("流媒体账号或地址已更新，请重新选择歌曲");
    const source = await adapter.preparePlayback(config, trackId, sessionId);
    if (options?.playback) {
      beginStreamingPlayback({
        serverId,
        trackId,
        sessionId,
        mediaSourceId: source.mediaSourceId,
        durationMs: source.durationMs,
      });
    }
    return { url: source.url, headers: playbackHeaders(config), sessionId };
  });
};

/**
 * 把 streaming:// 占位符解析为下载地址
 * @param streamingUrl - 渲染层生成的音源身份
 * @returns 原文件下载地址
 */
const resolveDownload = async (streamingUrl: string): Promise<string> => {
  const { serverId, trackId, serverRevision } = parseStreamingSource(streamingUrl);
  return withStreamingAdapter(serverId, async (config, adapter) => {
    if ((config.mediaRevision ?? 0) !== serverRevision)
      throw new Error("流媒体账号或地址已更新，请重新选择歌曲");
    return adapter.getDownloadUrl(config, trackId);
  });
};

/**
 * 生成带鉴权的真实封面地址
 * @param serverId - 服务器 ID
 * @param coverId - 服务端封面 ID
 * @param size - 目标尺寸
 * @param tag - 封面版本标识
 * @returns 真实封面地址；失败时返回 null
 */
const coverUrl = async (
  serverId: string,
  coverId: string,
  size = 300,
  tag?: string,
): Promise<string | null> => {
  if (!coverId) return null;
  const normalized = Math.min(2000, Math.max(32, Number(size) || 300));
  try {
    return await withStreamingAdapter(serverId, (config, adapter) =>
      adapter.getCoverUrl(config, coverId, normalized, tag),
    );
  } catch {
    return null;
  }
};

/** 与 bridge.js 约定的对外接口 */
interface StreamingApi {
  setNativeCall: (fn: NativeCall | null) => void;
  handle: (method: string, args: unknown[]) => Promise<unknown>;
  resolveSource: (
    streamingUrl: string,
    options?: { playback?: boolean },
  ) => Promise<{ url: string; headers?: Record<string, string>; sessionId: string }>;
  resolveDownload: (streamingUrl: string) => Promise<string>;
  coverUrl: (serverId: string, coverId: string, size?: number, tag?: string) => Promise<string | null>;
  playbackStop: (serverId?: string) => Promise<void>;
}

const api: StreamingApi = {
  setNativeCall: (fn) => {
    nativeCall = fn;
  },
  handle: async (method, args) => {
    const handler = handlers[method];
    if (!handler) throw new Error(`streaming.${method} 暂未在 Android 端实现`);
    return handler(...(args ?? []));
  },
  resolveSource,
  resolveDownload,
  coverUrl,
  playbackStop: (serverId?: string) => stopStreamingPlayback(serverId),
};

(globalThis as unknown as { StreamingBridge: StreamingApi }).StreamingBridge = api;

// 原生播放事件驱动播放上报；bundle 在 player.load 解析阶段加载，能覆盖整段播放
const playerApi = (globalThis as unknown as { api?: { player?: { onEvent?: (cb: typeof onPlayerEvent) => void } } })
  .api?.player;
if (playerApi && typeof playerApi.onEvent === "function") playerApi.onEvent(onPlayerEvent);

console.info("[streaming-bundle] ready");
