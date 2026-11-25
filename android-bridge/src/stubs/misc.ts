/**
 * Android 端杂项 stub：paths / broadcast / protocol / fs / atomically / coverProtocol。
 * 文件读写映射到 localStorage（键前缀 splayer:file:），保证配置持久化语义。
 */

// MARK: - @main/utils/paths

export const configDir = "/config";

// MARK: - @main/utils/broadcast

/** 原版向所有窗口广播；Android 端单 WebView，直接分发给 bridge.js 的订阅者 */
export const sendToMain = (channel: string, payload?: unknown): void => {
  try {
    const dispatch = (globalThis as { __splayerDispatch?: (ch: string, payload: unknown) => void })
      .__splayerDispatch;
    dispatch?.(channel, payload ?? null);
  } catch {
    // 桥未就绪时忽略
  }
};

// MARK: - @main/utils/protocol

export const MAIN_PARTITION = "persist:splayer-main";

// MARK: - node:fs（映射 localStorage）

const fileKey = (p: string): string => `splayer:file:${p}`;

const errnoException = (code: string, p: string): Error => {
  const e = new Error(`${code}: ${p}`) as Error & { code: string };
  e.code = code;
  return e;
};

export const existsSync = (p: string): boolean => localStorage.getItem(fileKey(p)) !== null;

export const readFileSync = (p: string, encoding?: string): string | Buffer => {
  const raw = localStorage.getItem(fileKey(p));
  if (raw === null) throw errnoException("ENOENT", p);
  if (encoding) return raw;
  return { length: raw.length } as unknown as Buffer;
};

export const writeFileSync = (p: string, data: string): void => {
  localStorage.setItem(fileKey(p), typeof data === "string" ? data : String(data));
};

export const mkdirSync = (): void => {};
export const mkdir = (
  p: string,
  opts: unknown,
  cb?: (e: Error | null) => void,
): void => {
  if (typeof opts === "function") opts(null);
  else cb?.(null);
};
export const statSync = (p: string): { isDirectory: () => boolean; size: number } => {
  const raw = localStorage.getItem(fileKey(p));
  if (raw === null) throw errnoException("ENOENT", p);
  return { isDirectory: () => false, size: raw.length };
};
export const unlinkSync = (p: string): void => {
  localStorage.removeItem(fileKey(p));
};
export const rmSync = (p: string, opts?: unknown): void => {
  void opts;
  localStorage.removeItem(fileKey(p));
};
export const readdirSync = (): string[] => [];
export const createWriteStream = (): unknown => ({
  write: () => {},
  end: () => {},
  on: () => {},
});
export const createReadStream = (): unknown => ({
  on: () => {},
  pipe: () => {},
});
export const promises = {
  readFile: async (p: string, encoding?: string): Promise<string | Buffer> =>
    readFileSync(p, encoding),
  writeFile: async (p: string, data: string): Promise<void> => writeFileSync(p, data),
  unlink: async (p: string): Promise<void> => unlinkSync(p),
  mkdir: async (): Promise<void> => {},
  stat: async (p: string): Promise<{ isDirectory: () => boolean; size: number }> => statSync(p),
  readdir: async (): Promise<string[]> => [],
};

// MARK: - atomically

/** 原版原子写文件；Android 端直接落 localStorage */
export const atomicWrite = (p: string, data: string): void => writeFileSync(p, data);

// MARK: - @main/services/streaming/coverProtocol

/** 原版注册 stream-cover:// 自定义协议；WebView 内不可注册，封面走直链/bridgeHttp */
export const registerStreamingCoverProtocol = (): void => {};

// MARK: - node:fs 默认导出

/** config.ts 使用 `import fs from "node:fs"`，需要默认导出 */
export default {
  existsSync,
  readFileSync,
  writeFileSync,
  mkdirSync,
  mkdir,
  statSync,
  unlinkSync,
  rmSync,
  readdirSync,
  createWriteStream,
  createReadStream,
  promises,
};
