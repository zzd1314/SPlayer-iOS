/** Android 端无桌面代理设置 */
export const getNetworkProxyUrl = (): string | null => null

/**
 * fetch 代理桩：主进程的 fetchWithProxy 原本经由 Electron 网络栈，
 * Android 端改为通过 Kotlin 桥发送请求以绕过 WebView 的 CORS 限制。
 */
export const fetchWithProxy = async (url: string, init?: {
  method?: string
  headers?: Record<string, string>
  body?: string
  signal?: unknown
}): Promise<unknown> => {
  const raw = await (globalThis as { __NeteaseHttp: { request: (u: string, o: unknown) => Promise<{ status: number, headers: Record<string, string>, setCookie: string[], bodyBase64: string }> } })
    .__NeteaseHttp.request(url, {
      method: init?.method ?? 'GET',
      headers: init?.headers ?? {},
      body: init?.body ?? '',
    })
  const text = base64ToUtf8(raw.bodyBase64)
  const lower: Record<string, string> = {}
  Object.entries(raw.headers ?? {}).forEach(([k, v]) => { lower[k.toLowerCase()] = v })
  return {
    ok: raw.status >= 200 && raw.status < 300,
    status: raw.status,
    statusText: '',
    headers: {
      get: (name: string) => {
        const key = name.toLowerCase()
        if (key === 'set-cookie') return raw.setCookie?.[0] ?? null
        return lower[key] ?? null
      },
      getSetCookie: () => raw.setCookie ?? [],
      has: (name: string) => (name.toLowerCase() === 'set-cookie' ? (raw.setCookie?.length ?? 0) > 0 : raw.headers?.[name.toLowerCase()] !== undefined),
    },
    arrayBuffer: async () => utf8ToArrayBuffer(text),
    text: async () => text,
    json: async () => JSON.parse(text),
  }
}

function base64ToUtf8(b64: string): string {
  if (!b64) return ''
  // URL 安全字符还原
  const norm = b64.replace(/-/g, '+').replace(/_/g, '/')
  const bin = atob(norm)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return new TextDecoder('utf-8').decode(bytes)
}

function utf8ToArrayBuffer(text: string): ArrayBuffer {
  return new TextEncoder().encode(text).buffer as ArrayBuffer
}