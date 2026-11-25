/**
 * Android 端流媒体快照暂存：替代上游使用 SQLite TEMP TABLE 的实现。
 * 同步期间数据留在内存，全部索引成功后再一次性发布到本地库；
 * 任何分页失败都不会触碰上一版可见快照。
 */
import type { Album, Artist, Playlist, Track } from "@shared/types/player";
import {
  beginStreamingLibraryBatch,
  deleteStaleAlbums,
  deleteStaleArtists,
  deleteStalePlaylists,
  deleteStaleTracks,
  endStreamingLibraryBatch,
  getStreamingMaxGeneration,
  upsertAlbums,
  upsertArtists,
  upsertPlaylists,
  upsertTracks,
} from "./stubs/db";

type Entry = Track | Album | Artist | Playlist;
type Kind = "songs" | "albums" | "artists" | "playlists";

interface Stage {
  entries: Record<Kind, Map<string, Entry>>;
  favorites: Map<string, boolean>;
}

const stages = new Map<string, Stage>();

const createStage = (): Stage => ({
  entries: {
    songs: new Map(),
    albums: new Map(),
    artists: new Map(),
    playlists: new Map(),
  },
  favorites: new Map(),
});

/** 开始暂存，清空该服务器上一轮未完成的分页 */
export const resetStreamingStage = (serverId: string): void => {
  stages.set(serverId, createStage());
};

/**
 * 记录同步期间用户刚确认的收藏，避免迟到的分页把它覆盖回旧状态
 * @param serverId - 服务器 ID
 * @param remoteId - 服务端歌曲 ID
 * @param favorite - 服务端确认的收藏状态
 */
export const recordStreamingStageFavorite = (
  serverId: string,
  remoteId: string,
  favorite: boolean,
): void => {
  const stage = stages.get(serverId);
  if (!stage) return;
  stage.favorites.set(remoteId, favorite);
};

/** 释放本次任务的全部暂存 */
export const clearStreamingStage = (serverId: string): void => {
  stages.delete(serverId);
};

/**
 * 暂存一页；重复或缺少 ID 直接中止同步，保留旧媒体库
 * @param serverId - 服务器 ID
 * @param kind - 索引类型
 * @param entries - 分页数据
 */
export const stageStreamingPage = (serverId: string, kind: Kind, entries: Entry[]): void => {
  let stage = stages.get(serverId);
  if (!stage) {
    stage = createStage();
    stages.set(serverId, stage);
  }
  const target = stage.entries[kind];
  for (const entry of entries) {
    const id = "source" in entry ? entry.originalId : entry.id;
    if (!id) throw new Error("服务器返回缺少 ID 的媒体条目");
    if (target.has(id)) throw new Error("服务器分页出现重复或缺少 ID，已保留旧媒体库");
    target.set(id, entry);
  }
};

/**
 * 所有索引成功后原子发布，失败时旧快照保持不变
 * @param serverId - 服务器 ID
 */
export const publishStreamingStage = (serverId: string): void => {
  const stage = stages.get(serverId);
  if (!stage) throw new Error("流媒体暂存已失效");
  const generation = Math.max(Date.now(), getStreamingMaxGeneration(serverId) + 1);
  beginStreamingLibraryBatch(serverId);
  try {
    const songs = [...stage.entries.songs.entries()].map(([remoteId, entry]) => {
      const track = entry as Track;
      return {
        serverId,
        remoteId,
        generation,
        track: stage.favorites.has(remoteId)
          ? { ...track, favorite: stage.favorites.get(remoteId) }
          : track,
      };
    });
    if (songs.length) upsertTracks(songs);
    const albums = [...stage.entries.albums.entries()].map(([remoteId, entry]) => ({
      serverId,
      remoteId,
      generation,
      album: entry as Album,
    }));
    if (albums.length) upsertAlbums(albums);
    const artists = [...stage.entries.artists.entries()].map(([remoteId, entry]) => ({
      serverId,
      remoteId,
      generation,
      artist: entry as Artist,
    }));
    if (artists.length) upsertArtists(artists);
    const playlists = [...stage.entries.playlists.entries()].map(([remoteId, entry]) => ({
      serverId,
      remoteId,
      generation,
      playlist: entry as Playlist,
    }));
    if (playlists.length) upsertPlaylists(playlists);
    deleteStaleTracks(serverId, generation);
    deleteStaleAlbums(serverId, generation);
    deleteStaleArtists(serverId, generation);
    deleteStalePlaylists(serverId, generation);
  } finally {
    endStreamingLibraryBatch(serverId);
  }
};
