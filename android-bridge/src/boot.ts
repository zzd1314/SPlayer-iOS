/**
 * WebView 运行时垫片，必须在其他模块之前执行：
 * - fetch → bridge.js 暴露的 window.__NeteaseHttp（Android 原生 bridgeHttp）
 * - AbortSignal.any / AbortSignal.timeout / crypto.randomUUID 兜底
 * - Buffer / process 全局
 */
import { Buffer } from "./stubs/buffer";

const globalScope = globalThis as Record<string, unknown>;

interface NativeHttpResult {
  status?: number;
  headers?: Record<string, string>;
  setCookie?: string[];
  bodyBase64?: string;
}

interface NativeHttp {
  request: (url: string, options: Record<string, unknown>) => Promise<NativeHttpResult>;
}

const abortedError = (): Error => {
  try {
    return new DOMException("Aborted", "AbortError");
  } catch {
    const error = new Error("Aborted");
    error.name = "AbortError";
    return error;
  }
};

const throwIfAborted = (signal?: AbortSignal | null): void => {
  if (!signal) return;
  if (signal.aborted) throw signal.reason ?? abortedError();
};

const headerPairs = (headers: unknown): [string, string][] => {
  if (!headers) return [];
  if (Array.isArray(headers)) {
    return headers
      .filter((item): item is [string, string] => Array.isArray(item) && item.length >= 2)
      .map(([key, value]) => [String(key), String(value)]);
  }
  if (typeof (headers as { forEach?: unknown }).forEach === "function") {
    const out: [string, string][] = [];
    (headers as { forEach: (cb: (value: string, key: string) => void) => void }).forEach(
      (value, key) => out.push([key, String(value)]),
    );
    return out;
  }
  return Object.entries(headers as Record<string, unknown>).map(([key, value]) => [
    key,
    String(value),
  ]);
};

const createHeaders = (raw: Record<string, string>, setCookie: string[]) => {
  const lower = new Map<string, string>();
  for (const [key, value] of Object.entries(raw ?? {})) lower.set(key.toLowerCase(), String(value));
  const cookies = setCookie ?? [];
  return {
    get: (name: string): string | null => {
      const key = name.toLowerCase();
      if (key === "set-cookie") return cookies[0] ?? lower.get(key) ?? null;
      return lower.get(key) ?? null;
    },
    getSetCookie: (): string[] => cookies,
    has: (name: string): boolean => {
      const key = name.toLowerCase();
      return key === "set-cookie" ? cookies.length > 0 : lower.has(key);
    },
    forEach: (cb: (value: string, key: string) => void): void => {
      lower.forEach((value, key) => cb(value, key));
      if (cookies.length) cb(cookies.join(", "), "set-cookie");
    },
    entries: (): IterableIterator<[string, string]> => lower.entries(),
    keys: (): IterableIterator<string> => lower.keys(),
    values: (): IterableIterator<string> => lower.values(),
    [Symbol.iterator]: (): IterableIterator<[string, string]> => lower.entries(),
  };
};

const decodeBody = (bodyBase64: string | undefined): Uint8Array => {
  if (!bodyBase64) return new Uint8Array(0);
  return Buffer.from(bodyBase64, "base64");
};

const nativeFetch = async (input: unknown, init: RequestInit = {}): Promise<unknown> => {
  const native = (globalScope.__NeteaseHttp ??
    (globalScope.window as { __NeteaseHttp?: NativeHttp } | undefined)?.__NeteaseHttp) as
    | NativeHttp
    | undefined;
  if (!native?.request) throw new TypeError("Android 网络桥 __NeteaseHttp 未就绪");

  const requestLike = input as { url?: string; method?: string; headers?: unknown } | null;
  const url =
    typeof input === "string"
      ? input
      : input instanceof URL
        ? input.toString()
        : String(requestLike?.url ?? input);
  const method = String(init.method ?? requestLike?.method ?? "GET").toUpperCase();
  const headers: Record<string, string> = {};
  for (const [key, value] of headerPairs(init.headers ?? requestLike?.headers)) {
    headers[key] = value;
  }
  const rawBody = init.body;
  const body =
    rawBody == null
      ? ""
      : typeof rawBody === "string"
        ? rawBody
        : typeof URLSearchParams !== "undefined" && rawBody instanceof URLSearchParams
          ? rawBody.toString()
          : String(rawBody);

  throwIfAborted(init.signal);
  const result = await native.request(url, { method, headers, body });
  throwIfAborted(init.signal);

  const status = Number(result?.status) || 0;
  const bytes = decodeBody(result?.bodyBase64);
  const text = Buffer.from(bytes).toString("utf8");
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: "",
    url,
    redirected: false,
    type: "basic",
    headers: createHeaders(result?.headers ?? {}, result?.setCookie ?? []),
    bodyUsed: false,
    text: async (): Promise<string> => text,
    json: async (): Promise<unknown> => JSON.parse(text),
    arrayBuffer: async (): Promise<ArrayBuffer> =>
      bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer,
    clone: () => nativeFetch(input, init),
  };
};

globalScope.fetch = nativeFetch;
if (typeof globalScope.window === "object" && globalScope.window) {
  (globalScope.window as Record<string, unknown>).fetch = nativeFetch;
}

const webCrypto = (globalScope.crypto ?? {}) as Crypto;
try {
  if (!globalScope.crypto) globalScope.crypto = webCrypto;
  if (typeof webCrypto.getRandomValues !== "function") {
    (webCrypto as { getRandomValues: (array: ArrayBufferView) => ArrayBufferView }).getRandomValues = (
      array: ArrayBufferView,
    ): ArrayBufferView => {
      const view = new Uint8Array(array.buffer, array.byteOffset, array.byteLength);
      for (let i = 0; i < view.length; i++) view[i] = Math.floor(Math.random() * 256);
      return array;
    };
  }
  if (typeof webCrypto.randomUUID !== "function") {
    (webCrypto as { randomUUID: () => string }).randomUUID = () => {
      const bytes = new Uint8Array(16);
      webCrypto.getRandomValues(bytes);
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, "0"));
      return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex
        .slice(6, 8)
        .join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10).join("")}`;
    };
  }
} catch {
  // 运行时 crypto 不可扩展时保持原样
}

const AbortSignalCtor = globalScope.AbortSignal as
  | (typeof AbortSignal & {
      any?: (signals: AbortSignal[]) => AbortSignal;
      timeout?: (ms: number) => AbortSignal;
    })
  | undefined;
try {
  if (AbortSignalCtor) {
    if (typeof AbortSignalCtor.timeout !== "function") {
      AbortSignalCtor.timeout = (ms: number): AbortSignal => {
        const controller = new AbortController();
        setTimeout(() => {
          try {
            controller.abort(
              typeof DOMException !== "undefined"
                ? new DOMException("TimeoutError", "TimeoutError")
                : abortedError(),
            );
          } catch {
            controller.abort();
          }
        }, ms);
        return controller.signal;
      };
    }
    if (typeof AbortSignalCtor.any !== "function") {
      AbortSignalCtor.any = (signals: AbortSignal[]): AbortSignal => {
        const controller = new AbortController();
        for (const signal of signals) {
          if (signal.aborted) {
            controller.abort(signal.reason);
            break;
          }
          signal.addEventListener("abort", () => controller.abort(signal.reason), { once: true });
        }
        return controller.signal;
      };
    }
  }
} catch {
  // 运行时 AbortSignal 不可扩展时保持原样
}

if (!globalScope.Buffer) globalScope.Buffer = Buffer;
if (!globalScope.process) {
  globalScope.process = { env: { NODE_ENV: "production" } };
}
