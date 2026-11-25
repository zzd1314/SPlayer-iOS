// streaming-api.js 冒烟测试：Node 本地 mock Subsonic/Jellyfin + WebView 运行时垫片。
// 运行：node smoke.mjs（构建产物需先由 build-streaming.mjs 生成）
import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const ASSETS = path.resolve(
  process.env.SPLAYER_ASSETS ??
    path.join(here, "..", "android", "webview", "src", "main", "assets", "web", "assets"),
);
const ENTRY = path.join(ASSETS, "streaming-api.js");

const md5 = (text) => createHash("md5").update(text).digest("hex");
const PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
  "base64",
);
const AUDIO = Buffer.from("fLaC-mock-audio");

// MARK: - HTTP 辅助

const sendJson = (res, payload, status = 200) => {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
};

const sendBytes = (res, bytes, type = "application/octet-stream", status = 200) => {
  res.writeHead(status, { "content-type": type, "content-length": bytes.length });
  res.end(bytes);
};

const readBody = (req) =>
  new Promise((resolve) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
  });

const listen = (server) =>
  new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server.address().port)));

const close = (server) =>
  new Promise((resolve) => {
    server.closeAllConnections?.();
    server.close(() => resolve());
  });

// MARK: - Subsonic mock

const subState = {
  duplicate: false,
  favorites: new Set(["s2"]),
};

/** 记录 Subsonic scrobble 上报（start 与正式打卡） */
const subScrobbles = [];

const subSongs = [
  {
    id: "s1",
    title: "Alpha Song",
    artist: "Alpha Artist",
    artistId: "ar1",
    album: "Alpha Album",
    albumId: "al1",
    discNumber: 1,
    duration: 180,
    bitRate: 900,
    samplingRate: 44100,
    bitDepth: 16,
    channelCount: 2,
    suffix: "flac",
    size: 123456,
    coverArt: "cov1",
  },
  {
    id: "s2",
    title: "Beta Song",
    artist: "Alpha Artist",
    artistId: "ar1",
    album: "Alpha Album",
    albumId: "al1",
    discNumber: 1,
    duration: 210,
    coverArt: "cov2",
    suffix: "flac",
  },
  {
    id: "s3",
    title: "Gamma Tune",
    artist: "Beta Artist",
    artistId: "ar2",
    album: "Beta Album",
    albumId: "al2",
    duration: 150,
    coverArt: "cov3",
    suffix: "mp3",
  },
];

const subAlbums = [
  { id: "al1", name: "Alpha Album", artist: "Alpha Artist", coverArt: "alc1", songCount: 2, year: 2024 },
  { id: "al2", name: "Beta Album", artist: "Beta Artist", coverArt: "alc2", songCount: 1, year: 2023 },
];
const subArtists = [
  { id: "ar1", name: "Alpha Artist", albumCount: 1, coverArt: "arc1" },
  { id: "ar2", name: "Beta Artist", albumCount: 1, coverArt: "arc2" },
];
const subPlaylists = [
  { id: "pl1", name: "Alpha Playlist", songCount: 2, coverArt: "plc1", owner: "demo" },
  { id: "pl2", name: "Beta Playlist", songCount: 1, coverArt: "plc2", owner: "demo" },
];

const subsonicSong = (song) => ({
  ...song,
  starred: subState.favorites.has(song.id) ? "2024-01-01T00:00:00Z" : undefined,
});

const subsonicServer = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  const match = /^\/rest\/([A-Za-z0-9]+?)(?:\.view)?\/?$/.exec(url.pathname);
  if (!match) return sendJson(res, { error: "not found" }, 404);
  const endpoint = match[1];
  const username = url.searchParams.get("u");
  const salt = url.searchParams.get("s");
  const token = url.searchParams.get("t");
  if (username !== "demo" || !salt || token !== md5(`secret${salt}`))
    return sendJson(res, {
      "subsonic-response": {
        status: "failed",
        version: "1.16.1",
        error: { code: 40, message: "Wrong username or password" },
      },
    });
  const ok = (payload) => sendJson(res, { "subsonic-response": { status: "ok", version: "1.16.1", ...payload } });
  const limit = Number(url.searchParams.get("songCount") ?? url.searchParams.get("size") ?? 0);
  const offset = Number(url.searchParams.get("songOffset") ?? url.searchParams.get("offset") ?? 0);
  const page = (list, fallbackLimit = 100) =>
    list.slice(offset, offset + (limit || fallbackLimit));

  switch (endpoint) {
    case "ping":
      return ok({ openSubsonic: true, serverVersion: "0.52.0", version: "1.16.1" });
    case "getMusicFolders":
      return ok({ musicFolders: { musicFolder: [{ id: 1, name: "Music" }] } });
    case "getIndexes":
      return ok({ indexes: { index: [{ artist: [{ id: "ar1", name: "Alpha Artist" }] }], child: [] } });
    case "getMusicDirectory":
      return ok({ directory: { id: "ar1", child: subSongs.map((song) => ({ ...song, isDir: false })) } });
    case "search3": {
      if (subState.duplicate) return ok({ searchResult3: { song: [subSongs[0], subSongs[0]] } });
      const query = (url.searchParams.get("query") ?? "").toLowerCase();
      const matched = query
        ? subSongs.filter((song) =>
            [song.title, song.artist, song.album].some((value) =>
              String(value).toLowerCase().includes(query),
            ),
          )
        : subSongs;
      return ok({ searchResult3: { song: page(matched).map(subsonicSong) } });
    }
    case "getAlbumList2":
      return ok({ albumList2: { album: page(subAlbums, 500) } });
    case "getArtists":
      return ok({ artists: { index: [{ artist: subArtists }] } });
    case "getPlaylists":
      return ok({ playlists: { playlist: subPlaylists } });
    case "getAlbum": {
      const album = subAlbums.find((item) => item.id === url.searchParams.get("id"));
      if (!album) return ok({});
      return ok({
        album: {
          ...album,
          song: subSongs.filter((song) => song.albumId === album.id).map(subsonicSong),
        },
      });
    }
    case "getPlaylist": {
      const playlist = subPlaylists.find((item) => item.id === url.searchParams.get("id"));
      if (!playlist) return ok({});
      return ok({
        playlist: {
          ...playlist,
          entry: subSongs.slice(0, 2).map(subsonicSong),
        },
      });
    }
    case "getArtist": {
      const artist = subArtists.find((item) => item.id === url.searchParams.get("id"));
      if (!artist) return ok({});
      return ok({
        artist: { ...artist, album: subAlbums.filter((album) => album.artist === artist.name) },
      });
    }
    case "getSong": {
      const song = subSongs.find((item) => item.id === url.searchParams.get("id"));
      return ok(song ? { song: subsonicSong(song) } : {});
    }
    case "star":
    case "unstar": {
      const id = url.searchParams.get("id");
      if (endpoint === "star") subState.favorites.add(id);
      else subState.favorites.delete(id);
      return ok({});
    }
    case "getStarred2":
      return ok({
        starred2: {
          song: subSongs.filter((song) => subState.favorites.has(song.id)).map(subsonicSong),
        },
      });
    case "getLyricsBySongId":
      return ok({
        lyricsList: {
          structuredLyrics: [
            {
              synced: true,
              offset: 0,
              line: [
                { start: 0, value: "alpha line one" },
                { start: 1000, value: "alpha line two" },
              ],
            },
          ],
        },
      });
    case "getLyrics":
      return ok({ lyrics: { value: "legacy alpha lyrics" } });
    case "stream":
      return sendBytes(res, AUDIO, "audio/flac");
    case "download":
      return sendBytes(res, AUDIO, "application/octet-stream");
    case "getCoverArt":
      return sendBytes(res, PNG, "image/png");
    case "scrobble":
      subScrobbles.push({
        id: url.searchParams.get("id"),
        time: url.searchParams.get("time"),
        submission: url.searchParams.get("submission"),
      });
      return ok({});
    default:
      return sendJson(res, { error: `unsupported endpoint ${endpoint}` }, 404);
  }
});

// MARK: - Jellyfin mock

const jfState = {
  token: "jelly-token",
  userId: "jf-user",
  favorites: new Set(["js2"]),
};

const jfSongs = [
  {
    Id: "js1",
    Name: "Jelly Song",
    Album: "Jelly Album",
    AlbumId: "jal1",
    AlbumArtist: "Jelly Artist",
    Artists: ["Jelly Artist"],
    ArtistItems: [{ Id: "jar1", Name: "Jelly Artist" }],
    RunTimeTicks: 1_800_000_000,
    ParentIndexNumber: 1,
    IndexNumber: 1,
    ImageTags: { Primary: "jt1" },
    MediaSources: [
      {
        Id: "ms1",
        Container: "flac",
        Bitrate: 900_000,
        Size: 123_456,
        MediaStreams: [
          { Type: "Audio", SampleRate: 44_100, BitDepth: 16, Channels: 2, Codec: "flac" },
        ],
      },
    ],
  },
  {
    Id: "js2",
    Name: "Jelly Second",
    Album: "Jelly Album",
    AlbumId: "jal1",
    AlbumArtist: "Jelly Artist",
    Artists: ["Jelly Artist"],
    ArtistItems: [{ Id: "jar1", Name: "Jelly Artist" }],
    RunTimeTicks: 2_100_000_000,
    ParentIndexNumber: 1,
    IndexNumber: 2,
    ImageTags: { Primary: "jt2" },
    MediaSources: [
      {
        Id: "ms2",
        Container: "flac",
        Bitrate: 800_000,
        Size: 223_456,
        MediaStreams: [
          { Type: "Audio", SampleRate: 48_000, BitDepth: 24, Channels: 2, Codec: "flac" },
        ],
      },
    ],
  },
];

const jfAlbums = [
  {
    Id: "jal1",
    Name: "Jelly Album",
    AlbumArtist: "Jelly Artist",
    ChildCount: 2,
    ProductionYear: 2024,
    ImageTags: { Primary: "jat1" },
  },
];
const jfArtists = [
  { Id: "jar1", Name: "Jelly Artist", ChildCount: 1, ImageTags: { Primary: "jart1" } },
];
const jfPlaylists = [
  { Id: "jpl1", Name: "Jelly Playlist", ChildCount: 2, ImageTags: { Primary: "jpt1" } },
];

const jfSong = (song) => ({
  ...song,
  UserData: { IsFavorite: jfState.favorites.has(song.Id) },
});

const paginate = (req, list) => {
  const url = new URL(req.url, "http://127.0.0.1");
  const start = Number(url.searchParams.get("StartIndex") ?? 0);
  const limit = Number(url.searchParams.get("Limit") ?? list.length);
  return { items: list.slice(start, start + limit), total: list.length };
};

const jellyfinServer = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://127.0.0.1");
  const pathname = url.pathname;
  const method = req.method ?? "GET";

  if (pathname === "/System/Info/Public") return sendJson(res, { Version: "10.9.0" });
  if (pathname === "/Users/AuthenticateByName" && method === "POST") {
    const body = await readBody(req);
    let username = "";
    let password = "";
    try {
      const parsed = JSON.parse(body);
      username = parsed.Username;
      password = parsed.Pw;
    } catch {
      // 忽略非法 JSON
    }
    if (username !== "demo" || password !== "secret")
      return sendJson(res, { error: "invalid credentials" }, 401);
    return sendJson(res, { AccessToken: jfState.token, User: { Id: jfState.userId } });
  }
  if (pathname === `/Users/${jfState.userId}`) {
    return sendJson(res, { Id: jfState.userId, Name: "demo" });
  }
  const embyItems = /^\/Users\/[^/]+\/Items$/.test(pathname);
  if (pathname === "/Items" || embyItems) {
    const params = url.searchParams;
    const type = params.get("IncludeItemTypes");
    let list = [];
    if (type === "Audio") {
      list = jfSongs.filter((song) => {
        const parent = params.get("ParentId");
        const artist = params.get("ArtistIds");
        if (parent && song.AlbumId !== parent) return false;
        if (artist && !song.ArtistItems.some((item) => item.Id === artist)) return false;
        return true;
      });
    } else if (type === "MusicAlbum") {
      list = jfAlbums.filter((album) => {
        const artist = params.get("AlbumArtistIds");
        return !artist || album.AlbumArtist === jfArtists.find((a) => a.Id === artist)?.Name;
      });
    } else if (type === "Playlist") {
      list = jfPlaylists;
    }
    const page = paginate(req, list);
    return sendJson(res, {
      Items: page.items.map((item) => (type === "Audio" ? jfSong(item) : item)),
      TotalRecordCount: page.total,
    });
  }
  if (pathname === "/Artists") {
    const page = paginate(req, jfArtists);
    return sendJson(res, { Items: page.items, TotalRecordCount: page.total });
  }
  const playlistItems = /^\/Playlists\/([^/]+)\/Items$/.exec(pathname);
  if (playlistItems) {
    const withIds = jfSongs.map((song, index) => ({
      ...jfSong(song),
      PlaylistItemId: `pi${index + 1}`,
    }));
    const page = paginate(req, withIds);
    return sendJson(res, { Items: page.items, TotalRecordCount: page.total });
  }
  const favorite =
    /^\/UserFavoriteItems\/([^/]+)$/.exec(pathname) ??
    /^\/Users\/[^/]+\/FavoriteItems\/([^/]+)$/.exec(pathname);
  if (favorite) {
    const id = decodeURIComponent(favorite[1]);
    if (method === "POST") jfState.favorites.add(id);
    else if (method === "DELETE") jfState.favorites.delete(id);
    return sendJson(res, { IsFavorite: jfState.favorites.has(id) });
  }
  const stream = /^\/Audio\/([^/]+)\/stream$/.exec(pathname);
  if (stream) return sendBytes(res, AUDIO, "audio/flac");
  const lyrics = /^\/Audio\/([^/]+)\/Lyrics$/.exec(pathname);
  if (lyrics)
    return sendJson(res, {
      Metadata: { IsSynced: true },
      Lyrics: [
        { Start: 0, Text: "jelly line one" },
        { Start: 10_000_000, Text: "jelly line two" },
      ],
    });
  const image = /^\/Items\/([^/]+)\/Images\/Primary$/.exec(pathname);
  if (image) return sendBytes(res, PNG, "image/png");
  const download = /^\/Items\/([^/]+)\/Download$/.exec(pathname);
  if (download) return sendBytes(res, AUDIO, "application/octet-stream");
  const item =
    /^\/Items\/([^/]+)$/.exec(pathname) ??
    /^\/Users\/[^/]+\/Items\/([^/]+)$/.exec(pathname);
  if (item) {
    const id = decodeURIComponent(item[1]);
    const song = jfSongs.find((entry) => entry.Id === id);
    if (song) return sendJson(res, jfSong(song));
    const album = jfAlbums.find((entry) => entry.Id === id);
    if (album) return sendJson(res, album);
    const playlist = jfPlaylists.find((entry) => entry.Id === id);
    if (playlist) return sendJson(res, playlist);
    return sendJson(res, { error: "not found" }, 404);
  }
  if (/^\/Sessions\/Playing/.test(pathname)) {
    res.writeHead(204);
    return res.end();
  }
  return sendJson(res, { error: `unsupported path ${pathname}` }, 404);
});

// MARK: - WebView 运行时垫片

class MemoryStorage {
  #map = new Map();
  quotaExceeded = false;
  getItem(key) {
    return this.#map.has(key) ? this.#map.get(key) : null;
  }
  setItem(key, value) {
    if (this.quotaExceeded) {
      const error = new Error("QuotaExceededError");
      error.name = "QuotaExceededError";
      throw error;
    }
    this.#map.set(key, String(value));
  }
  removeItem(key) {
    this.#map.delete(key);
  }
  clear() {
    this.#map.clear();
  }
  key(index) {
    return [...this.#map.keys()][index] ?? null;
  }
  keys() {
    return [...this.#map.keys()];
  }
  get length() {
    return this.#map.size;
  }
}

const storage = new MemoryStorage();
const nodeFetch = globalThis.fetch.bind(globalThis);
const events = [];
const waiters = [];

globalThis.localStorage = storage;
globalThis.window = globalThis;
globalThis.self = globalThis;
// 模拟 bridge.js 暴露的 window.api.player.onEvent，用于驱动播放上报
const playerListeners = [];
// 模拟原生 Android Keystore 通道（SecureStore）
const sealedValues = new Map();
globalThis.api = {
  player: { onEvent: (cb) => playerListeners.push(cb) },
  system: {
    secureEncrypt: async (plain) => {
      const sealed = Buffer.from(String(plain), "utf8").toString("base64");
      sealedValues.set(sealed, String(plain));
      return { value: sealed };
    },
    secureDecrypt: async (sealed) => {
      const plain = sealedValues.get(String(sealed));
      if (plain === undefined) throw new Error("decrypt failed");
      return { value: plain };
    },
  },
};
const emitPlayer = (type, data = {}) => {
  for (const cb of [...playerListeners]) cb({ type, data });
};
const waitFor = async (predicate, timeout = 3000) => {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (predicate()) return true;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  return predicate();
};
globalThis.__splayerDispatch = (channel, payload) => {
  events.push({ channel, payload });
  for (const waiter of [...waiters]) {
    if (waiter.channel === channel && waiter.predicate(payload)) {
      clearTimeout(waiter.timer);
      waiters.splice(waiters.indexOf(waiter), 1);
      waiter.resolve({ channel, payload });
    }
  }
};
globalThis.__NeteaseHttp = {
  async request(url, options = {}) {
    const init = { method: options.method ?? "GET", headers: options.headers ?? {} };
    if (options.body && init.method !== "GET" && init.method !== "HEAD") init.body = options.body;
    const response = await nodeFetch(url, init);
    const buffer = Buffer.from(await response.arrayBuffer());
    const headers = {};
    response.headers.forEach((value, key) => {
      headers[key] = value;
    });
    const setCookie =
      typeof response.headers.getSetCookie === "function" ? response.headers.getSetCookie() : [];
    return {
      status: response.status,
      headers,
      setCookie,
      bodyBase64: buffer.toString("base64"),
    };
  },
};

const waitEvent = (channel, predicate = () => true, timeout = 10_000) =>
  new Promise((resolve, reject) => {
    const waiter = { channel, predicate, resolve };
    waiter.timer = setTimeout(() => {
      const index = waiters.indexOf(waiter);
      if (index >= 0) waiters.splice(index, 1);
      reject(new Error(`等待事件超时: ${channel}`));
    }, timeout);
    waiters.push(waiter);
  });

// MARK: - 断言

let total = 0;
let passed = 0;
const failures = [];

const check = (name, predicate) => {
  total += 1;
  try {
    if (!predicate()) throw new Error("断言返回 false");
    passed += 1;
  } catch (error) {
    failures.push(`${name}: ${error instanceof Error ? error.message : String(error)}`);
  }
};

// MARK: - 主流程

const run = async () => {
  if (!fs.existsSync(ENTRY)) throw new Error(`未找到构建产物: ${ENTRY}`);
  const source = fs.readFileSync(ENTRY, "utf8");
  if (/\bfrom\s*["']\.\//.test(source) || /\bimport\s*\(\s*["']\.\//.test(source))
    throw new Error("streaming-api.js 含相对导入，不是单文件产物");

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "splayer-streaming-smoke-"));
  fs.writeFileSync(path.join(tempDir, "package.json"), '{"type":"module"}');
  fs.copyFileSync(ENTRY, path.join(tempDir, "streaming-api.js"));
  await import(pathToFileURL(path.join(tempDir, "streaming-api.js")).href);

  const bridge = globalThis.StreamingBridge;
  check("暴露 StreamingBridge", () => Boolean(bridge));
  check("契约方法齐全", () =>
    ["setNativeCall", "handle", "resolveSource", "resolveDownload", "coverUrl", "playbackStop"].every(
      (key) => typeof bridge?.[key] === "function",
    ),
  );
  const handle = (method, ...args) => bridge.handle(method, args);

  const subPort = await listen(subsonicServer);
  const jfPort = await listen(jellyfinServer);
  const subBase = `http://127.0.0.1:${subPort}`;
  const jfBase = `http://127.0.0.1:${jfPort}`;

  const subInput = {
    name: "Mock Subsonic",
    type: "navidrome",
    url: subBase,
    username: "demo",
    password: "secret",
  };
  const jfInput = {
    name: "Mock Jellyfin",
    type: "jellyfin",
    url: jfBase,
    username: "demo",
    password: "secret",
  };

  // ----- Subsonic -----
  const sub = await handle("addServer", subInput);
  check("Subsonic addServer 返回 id", () => typeof sub.id === "string" && sub.id.length > 0);
  const loaded = await handle("loadServers");
  check("loadServers 包含服务器", () => loaded.servers.length === 1 && loaded.servers[0].id === sub.id);
  check("不回传明文密码", () =>
    loaded.servers.every((server) => !("password" in server) && server.hasPassword === true),
  );
  const configRaw = storage.getItem("splayer:file:/config/streaming.json") ?? "";
  check("配置写入假文件", () => configRaw.includes("safe:v1:"));
  check("配置不含明文密码", () => configRaw.length > 0 && !configRaw.includes("secret"));
  check("密码密文来自 Keystore", () => {
    const persisted = JSON.parse(configRaw);
    const envelope = persisted.servers?.[0]?.encryptedPassword ?? "";
    if (!envelope.startsWith("safe:v1:")) return false;
    const inner = Buffer.from(envelope.slice("safe:v1:".length), "base64").toString("utf8");
    return inner.startsWith("keystore:v1:");
  });
  check("Keystore 模式不落旧随机密钥", () => !storage.getItem("splayer:sec-key"));

  await handle("setActiveServer", sub.id);
  const active = await handle("loadServers");
  check("activeServerId 写入", () => active.activeServerId === sub.id);

  const subPing = await handle("testConnection", subInput, sub.id);
  check("Subsonic testConnection ok", () => subPing.ok === true);
  check("Subsonic 返回版本", () => Boolean(subPing.version));
  const subConnect = await handle("connect", sub.id);
  check("Subsonic connect ok", () => subConnect.ok === true);
  check("connect 写入 lastConnected", () => typeof subConnect.server.lastConnected === "number");

  const subCompleted = waitEvent(
    "streaming:syncState",
    (payload) => payload.serverId === sub.id && payload.state === "completed",
  );
  const subStarted = await handle("sync", sub.id, true);
  check("Subsonic sync 已启动", () => subStarted === true);
  await subCompleted;
  check("Subsonic 发出 libraryUpdated", () =>
    events.some((event) => event.channel === "streaming:libraryUpdated" && event.payload === sub.id),
  );

  let subSnap = await handle("getSnapshot", sub.id);
  check("Subsonic 歌曲 3 首", () => subSnap.songs.length === 3);
  check("Subsonic 专辑 2 张", () => subSnap.albums.length === 2);
  check("Subsonic 歌手 2 位", () => subSnap.artists.length === 2);
  check("Subsonic 歌单 2 个", () => subSnap.playlists.length === 2);
  check("歌曲 id 带 serverId 前缀", () => subSnap.songs.every((song) => song.id.startsWith(`${sub.id}:`)));
  check("初始服务端收藏保留", () => subSnap.songs.find((song) => song.originalId === "s2")?.favorite === true);
  const subTracksChunk = storage.getItem(`splayer:streaming.v1.lib.${sub.id}.tracks.0`);
  check("本地库按分块键存储", () => {
    if (!subTracksChunk) return false;
    const rows = JSON.parse(subTracksChunk);
    return (
      Array.isArray(rows) &&
      rows.length === 3 &&
      rows.every((row) => Array.isArray(row) && row.length === 3)
    );
  });
  check("本地库索引最后写入", () => {
    const index = JSON.parse(storage.getItem(`splayer:streaming.v1.lib.${sub.id}.index`) ?? "null");
    return index?.kinds?.tracks?.chunks === 1 && index?.kinds?.tracks?.count === 3;
  });

  const subCovers = [
    ...subSnap.songs.flatMap((song) => [song.cover, song.coverOriginal]),
    ...subSnap.albums.map((album) => album.cover),
    ...subSnap.artists.map((artist) => artist.avatar),
    ...subSnap.playlists.map((playlist) => playlist.cover),
  ].filter(Boolean);
  check("Subsonic 封面均为 http(s)", () =>
    subCovers.length > 0 && subCovers.every((url) => /^https?:\/\//.test(url)),
  );
  check("Subsonic 无 streaming-cover 伪 URL", () =>
    subCovers.every((url) => !url.startsWith("streaming-cover://")),
  );
  const subCoverUrl = new URL(subSnap.songs.find((song) => song.originalId === "s1").cover);
  check("Subsonic 封面走 getCoverArt", () => subCoverUrl.pathname.endsWith("/rest/getCoverArt"));
  check("Subsonic 封面带 u/t/s", () =>
    ["u", "t", "s"].every((key) => Boolean(subCoverUrl.searchParams.get(key))),
  );
  const subSnapAgain = await handle("getSnapshot", sub.id);
  check("Subsonic 封面 salt 稳定", () =>
    subSnapAgain.songs.find((song) => song.originalId === "s1").cover ===
    subSnap.songs.find((song) => song.originalId === "s1").cover,
  );

  const subSearch = await handle("search", sub.id, "Alpha");
  check("Subsonic 搜索命中歌曲", () => subSearch.songs.some((song) => song.title.includes("Alpha")));
  check("Subsonic 搜索命中专辑", () => subSearch.albums.some((album) => album.name.includes("Alpha")));
  check("Subsonic 搜索命中歌手", () =>
    subSearch.artists.some((artist) => artist.name.includes("Alpha")),
  );
  const subEmptySearch = await handle("search", sub.id, "   ");
  check("Subsonic 空搜索返回空", () =>
    subEmptySearch.songs.length === 0 &&
    subEmptySearch.albums.length === 0 &&
    subEmptySearch.artists.length === 0,
  );

  const subFavoriteEvent = waitEvent(
    "streaming:favoriteChanged",
    (payload) => payload.serverId === sub.id && payload.trackId === "s1" && payload.favorite === true,
  );
  const subFavorite = await handle("setFavorite", sub.id, "s1", true);
  check("Subsonic setFavorite 返回服务端状态", () => subFavorite === true);
  await subFavoriteEvent;
  subSnap = await handle("getSnapshot", sub.id);
  check("收藏事件后快照 favorite 更新", () =>
    subSnap.songs.find((song) => song.originalId === "s1")?.favorite === true,
  );
  check("收藏覆盖层已写入", () =>
    (storage.getItem(`splayer:streaming.v1.fav.${sub.id}`) ?? "").includes('"s1":true'),
  );

  const subTrack = subSnap.songs.find((song) => song.originalId === "s1");
  const subStreamingUrl = `streaming://${encodeURIComponent(sub.id)}/${encodeURIComponent("s1")}?revision=${subTrack.serverRevision ?? 0}`;
  const subSource = await bridge.resolveSource(subStreamingUrl);
  check("Subsonic resolveSource 返回 http", () =>
    /^https?:\/\//.test(subSource.url) && subSource.url.includes("/rest/stream"),
  );
  const subSourceUrl = new URL(subSource.url);
  check("Subsonic 播放地址带 u/t/s", () =>
    ["u", "t", "s"].every((key) => Boolean(subSourceUrl.searchParams.get(key))),
  );
  check("Subsonic headers 可为空", () =>
    !subSource.headers || Object.keys(subSource.headers).length === 0,
  );

  // ----- 播放上报（scrobble）：start → 达标正式打卡 → stopped 收尾 -----
  subScrobbles.length = 0;
  const subPlay = await bridge.resolveSource(subStreamingUrl, { playback: true });
  check("播放解析返回 sessionId", () =>
    typeof subPlay.sessionId === "string" && subPlay.sessionId.length > 0,
  );
  emitPlayer("status", { state: "playing", position: 0, duration: 2000 });
  const startSeen = await waitFor(() =>
    subScrobbles.some((item) => item.submission === "false" && item.id === "s1"),
  );
  check("Subsonic start 上报", () => startSeen);
  await new Promise((resolve) => setTimeout(resolve, 1100));
  emitPlayer("position", { position: 1100, duration: 2000 });
  const scrobbleSeen = await waitFor(() =>
    subScrobbles.some((item) => item.submission === "true" && item.id === "s1"),
  );
  check("Subsonic 收听达标后正式打卡", () => scrobbleSeen);
  const scrobbleTime = Number(subScrobbles.find((item) => item.submission === "true")?.time ?? 0);
  check("打卡时间戳为毫秒时间", () => scrobbleTime > 1_600_000_000_000);
  emitPlayer("status", { state: "stopped", position: 1200, duration: 2000 });
  let stopError = null;
  try {
    await bridge.playbackStop();
    await bridge.playbackStop();
  } catch (error) {
    stopError = error;
  }
  check("重复 playbackStop 安全", () => stopError === null);

  const subDownload = await bridge.resolveDownload(subStreamingUrl);
  check("Subsonic resolveDownload 返回 http", () =>
    /^https?:\/\//.test(subDownload) && subDownload.includes("/rest/download"),
  );
  let revisionRejected = false;
  try {
    await bridge.resolveDownload(subStreamingUrl.replace(/revision=\d+/, "revision=999"));
  } catch {
    revisionRejected = true;
  }
  check("revision 不一致拒绝", () => revisionRejected);

  const subBridgeCover = await bridge.coverUrl(sub.id, "cov1", 300);
  check("Subsonic coverUrl 直链", () =>
    typeof subBridgeCover === "string" &&
    /^https?:\/\//.test(subBridgeCover) &&
    subBridgeCover.includes("/rest/getCoverArt"),
  );

  const subAlbumSongs = await handle("getAlbumSongs", sub.id, "al1");
  check("Subsonic getAlbumSongs", () => subAlbumSongs.length === 2);
  const subPlaylistSongs = await handle("getPlaylistSongs", sub.id, "pl1");
  check("Subsonic getPlaylistSongs", () => subPlaylistSongs.length === 2);
  const subArtistAlbums = await handle("getArtistAlbums", sub.id, "ar1");
  check("Subsonic getArtistAlbums", () => subArtistAlbums.length === 1);
  const subArtistSongs = await handle("getArtistSongs", sub.id, "ar1");
  check("Subsonic getArtistSongs", () => subArtistSongs.length === 2);
  const subLyrics = await handle("getLyrics", sub.id, "s1");
  check("Subsonic 歌词", () => typeof subLyrics === "string" && subLyrics.includes("alpha line one"));

  const subBeforeFailure = await handle("getSnapshot", sub.id);
  subState.duplicate = true;
  const subFailed = waitEvent(
    "streaming:syncState",
    (payload) => payload.serverId === sub.id && payload.state === "failed",
  );
  await handle("sync", sub.id, true);
  const subFailure = await subFailed;
  check("重复 ID 同步失败", () => String(subFailure.payload.error).includes("重复"));
  const subAfterFailure = await handle("getSnapshot", sub.id);
  check("失败同步保留旧快照", () =>
    subAfterFailure.songs.length === subBeforeFailure.songs.length &&
    subAfterFailure.songs.length === 3,
  );
  subState.duplicate = false;

  // ----- Jellyfin -----
  const jf = await handle("addServer", jfInput);
  check("Jellyfin addServer 返回 id", () => typeof jf.id === "string" && jf.id.length > 0);
  const jfPing = await handle("testConnection", jfInput, jf.id);
  check("Jellyfin testConnection ok", () => jfPing.ok === true);
  check("Jellyfin 返回版本", () => Boolean(jfPing.version));
  const jfConnect = await handle("connect", jf.id);
  check("Jellyfin connect ok", () => jfConnect.ok === true);

  const jfCompleted = waitEvent(
    "streaming:syncState",
    (payload) => payload.serverId === jf.id && payload.state === "completed",
  );
  await handle("sync", jf.id, true);
  await jfCompleted;
  check("Jellyfin 发出 libraryUpdated", () =>
    events.some((event) => event.channel === "streaming:libraryUpdated" && event.payload === jf.id),
  );

  let jfSnap = await handle("getSnapshot", jf.id);
  check("Jellyfin 歌曲 2 首", () => jfSnap.songs.length === 2);
  check("Jellyfin 专辑 1 张", () => jfSnap.albums.length === 1);
  check("Jellyfin 歌手 1 位", () => jfSnap.artists.length === 1);
  check("Jellyfin 歌单 1 个", () => jfSnap.playlists.length === 1);

  const jfCovers = [
    ...jfSnap.songs.flatMap((song) => [song.cover, song.coverOriginal]),
    ...jfSnap.albums.map((album) => album.cover),
    ...jfSnap.artists.map((artist) => artist.avatar),
    ...jfSnap.playlists.map((playlist) => playlist.cover),
  ].filter(Boolean);
  check("Jellyfin 封面均为 http(s)", () =>
    jfCovers.length > 0 && jfCovers.every((url) => /^https?:\/\//.test(url)),
  );
  check("Jellyfin 封面带 api_key", () =>
    jfCovers.every((url) => new URL(url).searchParams.has("api_key")),
  );
  check("Jellyfin 无 streaming-cover 伪 URL", () =>
    jfCovers.every((url) => !url.startsWith("streaming-cover://")),
  );

  const jfSearch = await handle("search", jf.id, "Jelly");
  check("Jellyfin 搜索命中歌曲", () => jfSearch.songs.length === 2);
  check("Jellyfin 搜索命中专辑", () => jfSearch.albums.length === 1);

  const jfFavoriteEvent = waitEvent(
    "streaming:favoriteChanged",
    (payload) => payload.serverId === jf.id && payload.trackId === "js1" && payload.favorite === true,
  );
  const jfFavorite = await handle("setFavorite", jf.id, "js1", true);
  check("Jellyfin setFavorite 返回服务端状态", () => jfFavorite === true);
  await jfFavoriteEvent;
  jfSnap = await handle("getSnapshot", jf.id);
  check("Jellyfin 收藏后快照更新", () =>
    jfSnap.songs.find((song) => song.originalId === "js1")?.favorite === true,
  );

  const jfTrack = jfSnap.songs.find((song) => song.originalId === "js1");
  const jfStreamingUrl = `streaming://${encodeURIComponent(jf.id)}/${encodeURIComponent("js1")}?revision=${jfTrack.serverRevision ?? 0}`;
  const jfSource = await bridge.resolveSource(jfStreamingUrl);
  check("Jellyfin resolveSource 返回 http", () =>
    /^https?:\/\//.test(jfSource.url) && jfSource.url.includes("/Audio/js1/stream"),
  );
  const jfSourceUrl = new URL(jfSource.url);
  check("Jellyfin 播放地址带 ApiKey 或 Authorization", () =>
    jfSourceUrl.searchParams.has("ApiKey") ||
    jfSourceUrl.searchParams.has("api_key") ||
    Boolean(jfSource.headers?.Authorization || jfSource.headers?.["X-Emby-Authorization"]),
  );

  const jfDownload = await bridge.resolveDownload(jfStreamingUrl);
  check("Jellyfin resolveDownload 返回 http", () =>
    /^https?:\/\//.test(jfDownload) && jfDownload.includes("/Items/js1/Download"),
  );
  const jfBridgeCover = await bridge.coverUrl(jf.id, "js1", 300, "jt1");
  check("Jellyfin coverUrl 直链", () =>
    typeof jfBridgeCover === "string" &&
    /^https?:\/\//.test(jfBridgeCover) &&
    jfBridgeCover.includes("/Items/js1/Images/Primary"),
  );

  const jfAlbumSongs = await handle("getAlbumSongs", jf.id, "jal1");
  check("Jellyfin getAlbumSongs", () => jfAlbumSongs.length === 2);
  const jfPlaylistSongs = await handle("getPlaylistSongs", jf.id, "jpl1");
  check("Jellyfin getPlaylistSongs", () => jfPlaylistSongs.length === 2);
  const jfArtistAlbums = await handle("getArtistAlbums", jf.id, "jar1");
  check("Jellyfin getArtistAlbums", () => jfArtistAlbums.length === 1);
  const jfArtistSongs = await handle("getArtistSongs", jf.id, "jar1");
  check("Jellyfin getArtistSongs", () => jfArtistSongs.length === 2);
  const jfLyrics = await handle("getLyrics", jf.id, "js1");
  check("Jellyfin 歌词", () => typeof jfLyrics === "string" && jfLyrics.includes("jelly line one"));

  // ----- Emby（与 Jellyfin 共用 API 契约，仅鉴权头与参数名不同） -----
  const embyInput = {
    name: "Mock Emby",
    type: "emby",
    url: jfBase,
    username: "demo",
    password: "secret",
  };
  const emby = await handle("addServer", embyInput);
  check("Emby addServer 返回 id", () => typeof emby.id === "string" && emby.id.length > 0);
  const embyPing = await handle("testConnection", embyInput, emby.id);
  check("Emby testConnection ok", () => embyPing.ok === true);
  const embyConnect = await handle("connect", emby.id);
  check("Emby connect ok", () => embyConnect.ok === true);

  const embyCompleted = waitEvent(
    "streaming:syncState",
    (payload) => payload.serverId === emby.id && payload.state === "completed",
  );
  await handle("sync", emby.id, true);
  await embyCompleted;

  const embySnap = await handle("getSnapshot", emby.id);
  check("Emby 歌曲 2 首", () => embySnap.songs.length === 2);
  const embyCovers = [
    ...embySnap.songs.flatMap((song) => [song.cover, song.coverOriginal]),
    ...embySnap.albums.map((album) => album.cover),
  ].filter(Boolean);
  check("Emby 封面带 api_key", () =>
    embyCovers.length > 0 && embyCovers.every((url) => new URL(url).searchParams.has("api_key")),
  );

  const embyTrack = embySnap.songs.find((song) => song.originalId === "js1");
  const embyStreamingUrl = `streaming://${encodeURIComponent(emby.id)}/${encodeURIComponent("js1")}?revision=${embyTrack.serverRevision ?? 0}`;
  const embySource = await bridge.resolveSource(embyStreamingUrl);
  check("Emby resolveSource 返回 http", () =>
    /^https?:\/\//.test(embySource.url) && embySource.url.includes("/Audio/js1/stream"),
  );
  check("Emby 播放地址带 api_key", () => new URL(embySource.url).searchParams.has("api_key"));
  check("Emby 请求头用 X-Emby-Authorization", () =>
    typeof embySource.headers?.["X-Emby-Authorization"] === "string",
  );
  const embyDownload = await bridge.resolveDownload(embyStreamingUrl);
  check("Emby resolveDownload 返回 http", () =>
    /^https?:\/\//.test(embyDownload) && embyDownload.includes("/Items/js1/Download"),
  );
  check("Emby 下载地址带 api_key", () =>
    new URL(embyDownload).searchParams.has("api_key"),
  );
  await handle("removeServer", emby.id);

  // ----- 更新身份清空本地库 / 删除服务器 -----
  const jfBeforeUpdate = jfSnap.songs.length;
  const jfUpdated = await handle("updateServer", jf.id, {
    ...jfInput,
    name: "Mock Jellyfin Renamed",
    password: "newsecret",
  });
  check("updateServer 提升 mediaRevision", () => jfUpdated.mediaRevision > (jf.mediaRevision ?? 0));
  const jfCleared = await handle("getSnapshot", jf.id);
  check("身份变更清空本地库", () =>
    jfBeforeUpdate > 0 &&
    jfCleared.songs.length === 0 &&
    jfCleared.albums.length === 0 &&
    jfCleared.artists.length === 0 &&
    jfCleared.playlists.length === 0,
  );
  check("清空后收藏覆盖层移除", () => storage.getItem(`splayer:streaming.v1.fav.${jf.id}`) === null);
  check("清空后分块键移除", () =>
    storage
      .keys()
      .every(
        (key) =>
          !key.startsWith(`splayer:streaming.v1.lib.${jf.id}.`) &&
          key !== `splayer:streaming.v1.fav.${jf.id}`,
      ),
  );

  const subDisconnected = await handle("disconnect", sub.id);
  check("disconnect 返回 undefined", () => subDisconnected === undefined);
  const subReconnect = await handle("connect", sub.id);
  check("disconnect 后仍可重连", () => subReconnect.ok === true);

  await handle("removeServer", jf.id);
  const finalList = await handle("loadServers");
  check("removeServer 移除配置", () => !finalList.servers.some((server) => server.id === jf.id));
  const removedSnap = await handle("getSnapshot", jf.id);
  check("removeServer 后快照为空", () =>
    removedSnap.songs.length === 0 && removedSnap.playlists.length === 0,
  );

  storage.quotaExceeded = true;
  const quotaWarning = waitEvent(
    "streaming:syncState",
    (payload) => payload.serverId === sub.id && typeof payload.warning === "string",
  );
  const quotaCompleted = waitEvent(
    "streaming:syncState",
    (payload) => payload.serverId === sub.id && payload.state === "completed",
  );
  await handle("sync", sub.id, true);
  const quotaEvent = await quotaWarning;
  check("QuotaExceeded 降级内存并告警", () => quotaEvent.payload.warning.includes("内存"));
  await quotaCompleted;
  const quotaSnap = await handle("getSnapshot", sub.id);
  check("降级后内存快照仍可读", () => quotaSnap.songs.length === 3);
  storage.quotaExceeded = false;

  let unknownRejected = false;
  try {
    await handle("stopStreamingPlayer", "x");
  } catch {
    unknownRejected = true;
  }
  check("未实现的 stopStreamingPlayer 被拒绝", () => unknownRejected);

  await close(subsonicServer);
  await close(jellyfinServer);
  fs.rmSync(tempDir, { recursive: true, force: true });
};

try {
  await run();
} catch (error) {
  failures.push(`FATAL: ${error instanceof Error ? `${error.message}\n${error.stack}` : String(error)}`);
}

console.log(`\nPASS ${passed}/${total} checks`);
if (failures.length) {
  console.log(`FAIL ${failures.length}`);
  for (const failure of failures) console.log(`  - ${failure}`);
  process.exitCode = 1;
} else {
  console.log("ALL CHECKS PASSED");
}
