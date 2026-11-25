/**
 * window.api 兼容桥：在 WebView 内还原 Electron preload 的 IPC 契约。
 * 任何命名空间的方法调用都会转发到 SPlayerNative（Kotlin），
 * 网易云 API 由同目录 netease-api.js（主进程模块的浏览器构建）接管。
 */
(() => {
  const native = window.SPlayerNative
  if (!native) return

  const pending = new Map()
  let seq = 0
  const listeners = new Map()

  // 窄屏适配：上游设置弹窗左栏固定 280px、右侧设置项又是「文字 + 固定 200px 控件」两列，
  // 手机宽度下右栏被挤成竖排。这里只做窄屏收窄与换行，不改任何上游样式与功能
  const mobileCss = `
@media (max-width: 720px) {
  [role="dialog"]:has(.w-70) { width: calc(100vw - 12px) !important; max-width: none !important; }
  [role="dialog"] .w-70 { width: 116px !important; padding: 12px 6px !important; }
  [role="dialog"] .w-70 .text-2xl { font-size: 15px !important; line-height: 1.3 !important; }
  [role="dialog"] .w-70 .text-sm { font-size: 10px !important; margin-bottom: 8px !important; }
  [role="dialog"] .w-70 .px-3 { padding-left: 6px !important; padding-right: 6px !important; }
  [role="dialog"] .w-70 .gap-2 { gap: 6px !important; }
  [role="dialog"] .py-6.px-8 { padding: 14px 10px !important; }
  [role="dialog"] .py-6.px-8 .justify-between { flex-wrap: wrap !important; }
  [role="dialog"] .py-6.px-8 .justify-between > .shrink-0 { width: 100% !important; justify-content: flex-start !important; }
}
`
  const mobileStyle = document.createElement('style')
  mobileStyle.id = 'splayer-mobile-layout'
  mobileStyle.textContent = mobileCss
  ;(document.head || document.documentElement).appendChild(mobileStyle)

  window.__splayerResolve = (callId, ok, payload, error) => {
    const p = pending.get(callId)
    if (!p) return
    pending.delete(callId)
    if (ok) p.resolve(payload)
    else {
      const err = new Error((error && error.message) || 'bridge error')
      p.reject(err)
    }
  }

  window.__splayerDispatch = (channel, payload) => {
    let data = payload
    if (typeof payload === 'string') {
      try { data = JSON.parse(payload) } catch (e) { data = payload }
    }
    const set = listeners.get(channel)
    if (!set) return
    set.forEach((cb) => {
      try { cb(data) } catch (e) { console.warn('[bridge] listener error', channel, e) }
    })
  }

  const call = (ns, method, args = []) => new Promise((resolve, reject) => {
    const id = 'c' + (++seq)
    pending.set(id, { resolve, reject })
    try {
      native.call(ns, method, id, JSON.stringify(args))
    } catch (e) {
      pending.delete(id)
      reject(e)
    }
  })

  // 网易云 bundle 的网络代理（绕过 WebView CORS）
  window.__NeteaseHttp = {
    request: (url, opts) => call('system', 'bridgeHttp', [
      url, (opts && opts.method) || 'GET', (opts && opts.headers) || {}, (opts && opts.body) || '',
    ]).then((r) => r || { status: 502, headers: {}, setCookie: [], bodyBase64: '' }),
  }

  /** preload 中已知的推送通道命名 */
  const EVENT_CHANNELS = {
    'player.onEvent': 'player:event',
    'system.onOpenSettings': 'system:openSettings',
    'system.onProtocolUrl': 'protocol:orpheus',
    'system.onOpenFiles': 'system:open-files',
    'system.onDropFiles': 'system:open-files',
    'nowPlaying.onTrackChange': 'nowPlaying:track-change',
    'nowPlaying.onLyricChange': 'nowPlaying:lyric-change',
    'nowPlaying.onPositionSync': 'nowPlaying:position-sync',
    'nowPlaying.onLyricOffsetChange': 'nowPlaying:lyric-offset-change',
    'window.onDesktopLyricVisibilityChange': 'desktopLyric:visibilityChange',
    'desktopLyric.onConfigChange': 'desktopLyric:configChange',
    'streaming.onFavoriteChanged': 'streaming:favoriteChanged',
    'streaming.onSyncState': 'streaming:syncState',
    'streaming.onLibraryUpdated': 'streaming:libraryUpdated',
    'update.onEvent': 'update:event',
    'recognition.onEvent': 'recognition:event',
    'plugins.onEvent': 'plugins:event',
  }

  const channelFor = (ns, method) => {
    const known = EVENT_CHANNELS[ns + '.' + method]
    if (known) return known
    return ns + ':' + method
      .replace(/^on/, '')
      .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
      .toLowerCase()
  }

  const subscribe = (ns, method, cb) => {
    const ch = channelFor(ns, method)
    let set = listeners.get(ch)
    if (!set) { set = new Set(); listeners.set(ch, set) }
    set.add(cb)
    return () => set.delete(cb)
  }

  /** 通用命名空间代理：onXxx → 订阅，其余 → 桥调用 */
  const makeNs = (ns) => new Proxy({}, {
    get(_t, prop) {
      if (typeof prop !== 'string' || prop === 'then' || prop === 'toJSON') return undefined
      if (prop.startsWith('on')) return (cb) => subscribe(ns, prop, cb)
      return (...args) => call(ns, prop, args)
    },
  })

  /** system：同步字段 + 异步方法混合 */
  const SYSTEM_SYNC = {
    platform: 'android',
    installType: 'android',
    osInfo: { type: 'Linux', arch: 'arm64', release: 'android' },
  }
  const systemNs = new Proxy(SYSTEM_SYNC, {
    get(_t, prop) {
      if (typeof prop !== 'string' || prop === 'then' || prop === 'toJSON') return undefined
      if (prop in SYSTEM_SYNC) return SYSTEM_SYNC[prop]
      if (prop.startsWith('on')) return (cb) => subscribe('system', prop, cb)
      return (...args) => call('system', prop, args)
    },
  })

  /** 网易云 bundle（netease-api.js）接管音源调用 */
  let neteasePromise = null
  const loadNetease = () => {
    if (!neteasePromise) {
      neteasePromise = import('/assets/assets/netease-api.js').then((mod) => {
        // 入口模块不依赖顶层 await（旧版 WebView 不支持 TLA），改为导出 ready Promise；
        // 老版本模块没有 default 时回退到全局变量
        return mod && mod.default ? mod.default : (window.__Netease || window.NeteaseBridge)
      }).then((b) => {
        if (!b) throw new Error('netease-api.js 未暴露 __Netease')
        return {
          call: async (platform, name, params) => {
            if (platform !== 'netease') {
              return { ok: false, error: platform + ' 音源暂未在 Android 端支持', status: 501 }
            }
            try {
              const r = await b.call(name, params || {})
              return { ok: true, status: r.status, body: r.body }
            } catch (e) {
              const resp = e && e.response
              if (resp) {
                return { ok: false, error: e.message, status: resp.status, body: resp.body }
              }
              return { ok: false, error: String((e && e.message) || e) }
            }
          },
          clearSession: () => { b.clearSession() },
          setCookie: (raw) => ({ ok: !!b.setCookie(raw) }),
        }
      }).catch((e) => { neteasePromise = null; throw e })
    }
    return neteasePromise
  }

  const apisNs = {
    call: (platform, name, params) => loadNetease().then((n) => n.call(platform, name, params)),
    clearSession: (platform) => loadNetease().then((n) => { if (platform === 'netease') n.clearSession() }),
    setCookie: (platform, raw) => loadNetease().then((n) => n.setCookie(platform === 'netease' ? raw : '')),
    openLoginWeb: async () => ({ ok: false, error: 'Android 端请使用扫码登录' }),
  }

  /** 歌词：优先走主进程同名逻辑的浏览器实现（网易云 LRC） */
  const lyricsNs = {
    matchById: async (platform, id) => {
      try {
        const n = await loadNetease()
        const r = await n.call('netease', 'lyric_new', { id: Number(id) })
        const body = r.body || {}
        const lrc = body.lrc && body.lrc.lyric
        const tlyric = body.tlyric && body.tlyric.lyric
        if (!lrc) return { ok: true, data: null }
        return {
          ok: true,
          data: {
            platform: 'netease',
            format: 'lrc',
            lyric: lrc,
            translation: tlyric || undefined,
          },
        }
      } catch (e) {
        return { ok: false, error: String((e && e.message) || e) }
      }
    },
  }

  /** 流媒体服务器 bundle（streaming-api.js）：复用上游主进程 streaming 服务层 */
  let streamingPromise = null
  const loadStreaming = () => {
    if (!streamingPromise) {
      streamingPromise = import('/assets/assets/streaming-api.js').then(() => {
        const b = window.StreamingBridge
        b.setNativeCall((ns, method, args) => call(ns, method, args))
        return b
      }).catch((e) => { streamingPromise = null; throw e })
    }
    return streamingPromise
  }

  const streamingNs = new Proxy({}, {
    get(_t, prop) {
      if (typeof prop !== 'string' || prop === 'then' || prop === 'toJSON') return undefined
      if (prop.startsWith('on')) return (cb) => subscribe('streaming', prop, cb)
      return (...args) => loadStreaming().then((b) => b.handle(prop, args))
    },
  })

  /**
   * 流媒体音源占位符 `streaming://<serverId>/<trackId>` 只有主进程 bundle 认识，
   * 原生播放/下载/缓存拿到的必须是带鉴权的真实 http(s) 地址，因此统一在桥上替换。
   */
  const resolveStreamingUrl = (url, mode) => {
    if (typeof url !== 'string' || !url.startsWith('streaming:')) return Promise.resolve(url)
    return loadStreaming().then((b) => {
      if (mode === 'download') return b.resolveDownload(url)
      return Promise.resolve(b.resolveSource(url)).then((r) => (r && r.url ? r.url : url))
    })
  }

  /** player：load 前解析流媒体源并透传请求头 */
  const playerNs = new Proxy({}, {
    get(_t, prop) {
      if (typeof prop !== 'string' || prop === 'then' || prop === 'toJSON') return undefined
      if (prop.startsWith('on')) return (cb) => subscribe('player', prop, cb)
      if (prop === 'load') {
        return async (source, options) => {
          const opts = Object.assign({}, options || {})
          if (typeof source === 'string' && source.startsWith('streaming:')) {
            const resolved = await loadStreaming().then((b) =>
              b.resolveSource(source, { playback: true }),
            )
            if (resolved && resolved.url) {
              if (resolved.headers && Object.keys(resolved.headers).length) {
                opts.httpHeaders = resolved.headers
              }
              return call('player', 'load', [resolved.url, opts])
            }
          }
          // 切到本地/其他音源时收尾流媒体播放上报；bundle 未加载则不触发加载
          if (streamingPromise) {
            streamingPromise
              .then((b) => b.playbackStop && b.playbackStop())
              .catch(() => {})
          }
          return call('player', 'load', [source, opts])
        }
      }
      return (...args) => call('player', prop, args)
    },
  })

  /** download：渲染层回传的 streaming:// 也要先换成真实地址（原生直接 HttpURLConnection 下载） */
  const downloadNs = new Proxy({}, {
    get(_t, prop) {
      if (typeof prop !== 'string' || prop === 'then' || prop === 'toJSON') return undefined
      if (prop.startsWith('on')) return (cb) => subscribe('download', prop, cb)
      if (prop === 'submitResolution') {
        return async (taskId, res) => {
          let payload = res
          if (res && typeof res.url === 'string' && res.url.startsWith('streaming:')) {
            try {
              payload = Object.assign({}, res, { url: await resolveStreamingUrl(res.url, 'download') })
            } catch (e) {
              console.warn('[bridge] 流媒体下载地址解析失败', e)
              return call('download', 'failResolution', [taskId])
            }
          }
          return call('download', 'submitResolution', [taskId, payload])
        }
      }
      return (...args) => call('download', prop, args)
    },
  })

  /** 缓存：song / download 为二级命名空间（preload 契约） */
  const cacheNs = new Proxy({}, {
    get(_t, prop) {
      if (typeof prop !== 'string' || prop === 'then' || prop === 'toJSON') return undefined
      if (prop === 'song') {
        return {
          lookup: (key) => call('cache', 'song:lookup', [key]),
          fetch: async (key, source, url, preloadId) => {
            const realUrl = await resolveStreamingUrl(url)
            return call('cache', 'song:fetch', [key, source, realUrl, preloadId])
          },
          cancel: (key) => call('cache', 'song:cancel', [key]),
        }
      }
      if (prop.startsWith('on')) return (cb) => subscribe('cache', prop, cb)
      return (...args) => call('cache', prop, args)
    },
  })

  window.api = new Proxy({}, {
    get(_t, ns) {
      if (typeof ns !== 'string' || ns === 'then' || ns === 'toJSON') return undefined
      if (ns === 'system') return systemNs
      if (ns === 'apis') return apisNs
      if (ns === 'lyrics') return lyricsNs
      if (ns === 'streaming') return streamingNs
      if (ns === 'cache') return cacheNs
      if (ns === 'player') return playerNs
      if (ns === 'download') return downloadNs
      return makeNs(ns)
    },
  })

  console.info('[bridge] window.api shim ready')
})()
