/**
 * 流媒体播放上报（scrobble）状态机。
 *
 * 上游由 Electron 主进程监听媒体状态驱动上报；Android 播放在原生 Media3 完成，
 * 这里订阅桥梁转发的 player:event（status/position/seek/ended/next/prev/sourceError），
 * 还原上游 playback.ts 的时序，复用 StreamingPlaybackSession 的阈值与合并规则：
 * - 首次真正播放才发送 start；
 * - 收听时长达到 min(时长/2, 4 分钟) 发送 scrobble（Subsonic 正式打卡）；
 * - 每 10 秒合并发送一次 progress，停止时补发 stop。
 */
import { withStreamingAdapter } from "@main/services/streaming/connection";
import { StreamingPlaybackSession } from "@main/services/streaming/playbackSession";
import type { StreamingPlaybackReport } from "@main/services/streaming/adapters/types";

interface PlaybackIdentity {
  trackId: string;
  sessionId: string;
  mediaSourceId?: string;
  durationMs: number;
}

interface ActivePlayback {
  serverId: string;
  identity: PlaybackIdentity;
  session: StreamingPlaybackSession;
  /** 上一段播放的收尾 Promise，新会话的 start 必须等它发完 */
  previousStop: Promise<void>;
  serverStarted: boolean;
}

let active: ActivePlayback | undefined;
let pendingStop: Promise<void> = Promise.resolve();
/** 原生引擎最近一次状态，用于 begin 时立即对齐（预加载期间可能是 paused） */
let lastState = "idle";

/** 单次上报：失败只记录，不阻塞后续事件 */
const reportTo = async (entry: ActivePlayback, report: StreamingPlaybackReport): Promise<void> => {
  await entry.previousStop;
  // 串行队列里旧会话的 start 可能晚于新会话建立，丢弃已被替换的会话事件
  if (report.event === "start" && active !== entry) return;
  if ((report.event === "progress" || report.event === "stop") && !entry.serverStarted) return;
  try {
    await withStreamingAdapter(entry.serverId, async (config, adapter) => {
      await adapter.reportPlayback(config, {
        ...report,
        mediaSourceId: entry.identity.mediaSourceId,
      });
      if (report.event === "start") entry.serverStarted = true;
    });
  } catch (error) {
    console.warn("[streaming] 播放上报失败", entry.serverId, error);
  }
};

/**
 * 绑定一次新的流媒体播放（由 resolveSource 在 native load 前调用）
 * @param info - 服务器/歌曲/会话标识，sessionId 与播放地址里的保持一致
 */
export const beginStreamingPlayback = (info: {
  serverId: string;
  trackId: string;
  sessionId: string;
  mediaSourceId?: string;
  durationMs?: number;
}): void => {
  void stopStreamingPlayback();
  const identity: PlaybackIdentity = {
    trackId: info.trackId,
    sessionId: info.sessionId,
    mediaSourceId: info.mediaSourceId,
    durationMs: info.durationMs ?? 0,
  };
  const entry: ActivePlayback = {
    serverId: info.serverId,
    identity,
    previousStop: pendingStop,
    serverStarted: false,
    session: undefined as unknown as StreamingPlaybackSession,
  };
  entry.session = new StreamingPlaybackSession(identity, (report) => reportTo(entry, report));
  active = entry;
  entry.session.state(lastState === "playing");
};

/**
 * 收尾当前（或指定服务器）的播放会话
 * @param serverId - 只收尾指定服务器，省略则收尾当前会话
 */
export const stopStreamingPlayback = (serverId?: string): Promise<void> => {
  if (!active || (serverId && active.serverId !== serverId)) return pendingStop;
  const previous = active;
  active = undefined;
  pendingStop = previous.session.stop();
  return pendingStop;
};

/**
 * 原生播放事件入口
 * @param event - bridge 转发的 { type, data }
 */
export const onPlayerEvent = (event: { type?: string; data?: Record<string, unknown> }): void => {
  const type = event?.type;
  const data = event?.data ?? {};
  if (type === "status") {
    const state = String(data.state ?? "idle");
    lastState = state;
    if (state === "stopped" || state === "idle") {
      void stopStreamingPlayback();
      return;
    }
    if (!active) return;
    const duration = Number(data.duration ?? 0);
    if (duration > 0) active.identity.durationMs = duration;
    active.session.state(state === "playing");
    active.session.position(Number(data.position ?? 0));
    return;
  }
  if (!active) return;
  if (type === "position") {
    active.session.position(Number(data.position ?? 0));
    return;
  }
  if (type === "seek") {
    active.session.seek(Number(data.position ?? 0));
    return;
  }
  if (type === "ended" || type === "next" || type === "prev" || type === "sourceError") {
    void stopStreamingPlayback();
  }
};
