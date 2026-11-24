/**
 * Android WebView 端网易云 API 入口：
 * 完整复用主进程 modules + 加密层（eapi/xeapi/weapi），
 * 会话改存 localStorage，网络经 Kotlin 桥发送。
 */
import { buildCacheKey, cacheClear, cacheGet, cacheSet } from '@main/apis/netease/core/cache'
import { cookieToJson } from '@main/apis/netease/core/cookie'
import { getAnonymousToken, getDeviceId, setAnonymousToken, setDeviceId } from '@main/apis/netease/core/device'
import { createRequest } from '@main/apis/netease/core/request'
import { resetXeapiKey } from '@main/apis/netease/core/xeapi'
import { modules } from '@main/apis/netease/modules'
import { createOption, type Query } from '@main/apis/netease/core/option'
import { DOMAIN } from '@main/apis/netease/core/config'
import type { NeteaseRequestError } from '@main/apis/netease/core/response'

const SESSION_KEY = 'splayer:netease:session'

const SESSION_MUTATING = new Set([
  'login', 'login_cellphone', 'login_qr_check', 'login_refresh', 'logout',
  'register_anonimous', 'scrobble', 'song_like', 'artist_sub', 'album_sub',
  'playlist_subscribe', 'playlist_tracks',
])

const NON_CACHEABLE = new Set([
  'audio_match', 'captcha_sent', 'captcha_verify', 'login', 'login_cellphone',
  'login_qr_check', 'login_qr_create', 'login_refresh', 'login_status', 'logout',
  'register_anonimous', 'deviceinfo_center_upload', 'song_url', 'song_download_url',
  'scrobble', 'scrobble_v1', 'like', 'like_v1', 'song_like', 'likelist',
  'album_sublist', 'artist_sublist', 'user_level', 'user_record',
  'record_recent_song', 'artist_sub', 'playlist_create', 'playlist_delete',
  'playlist_tracks', 'playlist_subscribe', 'playlist_name_update',
  'playlist_desc_update', 'playlist_order_update', 'playlist_detail',
  'user_playlist', 'user_subcount', 'user_cloud', 'user_cloud_del',
  'cloud_upload_check', 'cloud_nos_token', 'cloud_upload_info', 'cloud_pub',
  'cloud_upload_check_v2', 'cloud_song_import', 'album_sub',
  'playmode_intelligence', 'personal_fm', 'fm_trash', 'recommend_songs',
])

const SESSIONLESS = new Set(['audio_match'])

let sessionCache: Record<string, string> | null = null
let sessionVersion = 0
let anonymousSessionPromise: Promise<void> | null = null

const loadSession = (): Record<string, string> => {
  if (!sessionCache) {
    try {
      sessionCache = JSON.parse(localStorage.getItem(SESSION_KEY) || '{}')
    } catch {
      sessionCache = {}
    }
    if (sessionCache.deviceId) setDeviceId(sessionCache.deviceId)
    setAnonymousToken(sessionCache.MUSIC_A || '')
  }
  return sessionCache!
}

const persistSession = (cookies: Record<string, string>): void => {
  sessionVersion++
  sessionCache = cookies
  if (cookies.deviceId) setDeviceId(cookies.deviceId)
  setAnonymousToken(cookies.MUSIC_A || '')
  try { localStorage.setItem(SESSION_KEY, JSON.stringify(cookies)) } catch { /* 存储满时忽略 */ }
}

const parseSetCookie = (arr: string[]): Record<string, string> => {
  const out: Record<string, string> = {}
  for (const raw of arr) {
    const first = raw.split(';')[0]
    const eq = first.indexOf('=')
    if (eq <= 0) continue
    out[first.slice(0, eq).trim()] = first.slice(eq + 1).trim()
  }
  return out
}

export const ensureAnonymousSession = async (): Promise<void> => {
  const state = loadSession()
  if (state.MUSIC_U || state.MUSIC_A || getAnonymousToken()) return
  if (anonymousSessionPromise) return anonymousSessionPromise
  anonymousSessionPromise = (async () => {
    const session = loadSession()
    const result = await (modules as Record<string, (q: Query, r: unknown) => Promise<{ body: unknown, cookie?: string[] }>>)
      .register_anonimous({ cookie: { ...session } } as Query, createRequest)
    const body = result.body as { token?: unknown }
    const patch = parseSetCookie(result.cookie ?? [])
    const token = typeof body.token === 'string' ? body.token : patch.MUSIC_A
    if (!token) throw new Error('netease anonymous registration missing MUSIC_A')
    persistSession({ ...loadSession(), ...patch, MUSIC_A: token, deviceId: getDeviceId() })
    cacheClear()
  })().finally(() => { anonymousSessionPromise = null })
  return anonymousSessionPromise
}

const callNetease = async (
  name: string,
  params: Record<string, unknown> = {},
): Promise<{ status: number, body: unknown }> => {
  const rawPath = /^\/api\/[a-zA-Z0-9_/-]+$/.test(name)
  const registry = modules as Record<string, ((q: Query, r: unknown) => Promise<{ status: number, body: unknown, cookie?: string[] }>) | undefined>
  const fn = registry[name]
    ?? (rawPath
      ? (query: Query) => {
          const {
            cookie: _c, crypto: _cr, client: _cl, ua: _u, realIP: _r, ip: _i,
            domain: _d, checkToken: _ct, e_r: _e, ...data
          } = query as Record<string, unknown>
          const options = createOption(query, 'api')
          if (options.crypto === 'api') options.domain = DOMAIN
          return createRequest(name, data as Record<string, unknown>, options)
        }
      : undefined)
  if (!fn) throw new Error(`unknown netease api: ${name}`)

  const isSessionEndpoint = name.startsWith('login') || name.startsWith('captcha')
    || name === 'logout' || name === 'register_anonimous'
  if (!isSessionEndpoint && !SESSIONLESS.has(name) && params.cookie === undefined) {
    await ensureAnonymousSession()
  }
  const session = loadSession()

  const cacheable = !rawPath && !NON_CACHEABLE.has(name)
  const cacheKey = cacheable ? buildCacheKey(name, params) : ''
  if (cacheable) {
    const hit = cacheGet(cacheKey)
    if (hit) return hit as { status: number, body: unknown }
  }

  const query: Query = {
    ...params,
    cookie: typeof params.cookie === 'string'
      ? cookieToJson(params.cookie)
      : (params.cookie as Record<string, string> | undefined) || { ...session },
  } as Query

  const requestSessionVersion = sessionVersion
  const res = await fn(query, createRequest)
  if (requestSessionVersion !== sessionVersion) {
    return { status: res.status, body: res.body }
  }

  if (SESSION_MUTATING.has(name)) {
    const patch = parseSetCookie(res.cookie ?? [])
    if (name === 'register_anonimous') {
      const token = (res.body as { token?: unknown })?.token
      if (typeof token === 'string') patch.MUSIC_A = token
      patch.deviceId = getDeviceId()
    }
    if (Object.keys(patch).length) {
      persistSession({ ...loadSession(), ...patch })
      cacheClear()
    }
  }

  const value = { status: res.status, body: res.body }
  if (cacheable && res.status === 200 && Number((res.body as { code?: unknown })?.code) === 200) {
    cacheSet(cacheKey, value)
  }
  return value
}

export const isNeteaseRequestError = (e: unknown): e is InstanceType<typeof NeteaseRequestError> =>
  e instanceof Error && 'response' in e

export const cookies = (): Record<string, string> => ({ ...loadSession() })

export const setCookieString = (raw: string): boolean => {
  const parsed = cookieToJson(raw)
  if (!parsed.MUSIC_U) return false
  persistSession({ ...loadSession(), ...parsed })
  cacheClear()
  return true
}

export const clearSession = (): void => {
  resetXeapiKey()
  sessionVersion++
  sessionCache = {}
  setAnonymousToken('')
  localStorage.removeItem(SESSION_KEY)
  cacheClear()
}

// 全局挂载，供 bridge.js 调用
;(globalThis as unknown as Record<string, unknown>).__Netease = {
  call: callNetease,
  cookies,
  setCookie: setCookieString,
  clearSession,
  ensureSession: ensureAnonymousSession,
}