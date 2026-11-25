// streaming-api.js 构建脚本：单文件 ESM（无代码分割、无相对 import）。
// 上游源码默认位于 splayer-next worktree，可用 SPLAYER_UPSTREAM 覆盖。
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
const UP =
  process.env.SPLAYER_UPSTREAM ??
  "C:/Users/Administrator/AppData/Local/Temp/splayer-next/SPlayer-Dev-SPlayer-Next-5772455";
const OUT =
  process.argv[2] ??
  process.env.SPLAYER_OUTFILE ??
  "C:/Users/Administrator/AppData/Local/Temp/splayer-android/android/webview/src/main/assets/web/assets/streaming-api.js";

/** 便携 esbuild：优先本地 node_modules，其次复用 netease-bundle 的工具链 */
const loadEsbuild = () => {
  const candidates = [
    process.env.SPLAYER_ESBUILD,
    path.join(here, "node_modules/esbuild"),
    "C:/Users/Administrator/AppData/Local/Temp/netease-bundle/node_modules/esbuild",
  ].filter(Boolean);
  for (const candidate of candidates) {
    try {
      return require(candidate);
    } catch {
      // 尝试下一个候选
    }
  }
  throw new Error("未找到 esbuild，请设置 SPLAYER_ESBUILD 或安装依赖");
};

const stub = (name) => path.join(here, "src/stubs", name);

const specific = {
  "@main/database": stub("db.ts"),
  "@main/database/streaming/tracks": stub("db.ts"),
  "@main/database/streaming/albums": stub("db.ts"),
  "@main/database/streaming/artists": stub("db.ts"),
  "@main/database/streaming/playlists": stub("db.ts"),
  "@main/utils/secureStorage": stub("secure.ts"),
  "@main/utils/paths": stub("misc.ts"),
  "@main/utils/broadcast": stub("misc.ts"),
  "@main/utils/protocol": stub("misc.ts"),
  "@main/services/streaming/coverProtocol": stub("misc.ts"),
  "@main/utils/proxy": stub("proxy.ts"),
  "@main/utils/logger": stub("logger.ts"),
  "@main/store": stub("store.ts"),
  "@main/window/main": stub("windowmain.ts"),
  electron: stub("electron.ts"),
  atomically: stub("misc.ts"),
  "node:crypto": stub("crypto.ts"),
  crypto: stub("crypto.ts"),
  "node:fs": stub("misc.ts"),
  fs: stub("misc.ts"),
  "node:path": stub("path.ts"),
  path: stub("path.ts"),
  "node:os": stub("os.ts"),
  os: stub("os.ts"),
  "node:zlib": stub("zlib.ts"),
  zlib: stub("zlib.ts"),
  "node:buffer": stub("buffer.ts"),
  buffer: stub("buffer.ts"),
};

const resolveUpstream = (specifier) => {
  const isMain = specifier.startsWith("@main/");
  const base = isMain
    ? path.join(UP, "electron", "main", specifier.slice("@main/".length))
    : path.join(UP, "shared", specifier.slice("@shared/".length));
  const candidates = [
    base,
    `${base}.ts`,
    `${base}.tsx`,
    `${base}.js`,
    path.join(base, "index.ts"),
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;
  }
  return null;
};

const replaceOnce = (text, regex, replacement, label) => {
  const flags = regex.flags.includes("g") ? regex.flags : `${regex.flags}g`;
  const count = (text.match(new RegExp(regex.source, flags)) ?? []).length;
  if (count !== 1) throw new Error(`${label} 封面地址替换失败：匹配到 ${count} 处`);
  return text.replace(regex, () => replacement);
};

const subsonicCover = `const coverUrl = (
  config: StreamingRuntimeConfig,
  coverId: string | undefined,
  size: number,
): string | undefined => {
  if (!coverId) return undefined;
  // 稳定 salt：避免每次生成不同 URL 导致封面缓存失效
  const salt = createHash("md5")
    .update(\`splayer-cover:\${config.id}:\${config.username}\`)
    .digest("hex")
    .slice(0, 12);
  const params = new URLSearchParams({
    u: config.username,
    t: createHash("md5").update(config.password + salt).digest("hex"),
    s: salt,
    v: API_VERSION,
    c: CLIENT_NAME,
    f: "json",
    id: coverId,
    size: String(size),
  });
  return \`\${config.url.replace(/\\/+$/, "")}/rest/getCoverArt?\${params.toString()}\`;
};`;

const jellyfinCover = `const imageUrl = (
  config: StreamingRuntimeConfig,
  itemId: string,
  tag: string | undefined,
  maxHeight: number,
): string | undefined => {
  const params = new URLSearchParams({ maxHeight: String(maxHeight) });
  params.set("api_key", config.accessToken!);
  if (tag) params.set("tag", tag);
  const coverId = encodeURIComponent(itemId);
  return \`\${config.url.replace(/\\/+$/, "")}/Items/\${coverId}/Images/Primary?\${params.toString()}\`;
};`;

const coverPlugin = {
  name: "streaming-cover-url",
  setup(esbuild) {
    esbuild.onLoad({ filter: /[\\/]adapters[\\/]subsonic\.ts$/ }, (args) => {
      const source = fs.readFileSync(args.path, "utf8");
      const contents = replaceOnce(
        source,
        /const coverUrl = \([\s\S]*?\n\};/,
        subsonicCover,
        "subsonic.coverUrl",
      );
      return { contents, loader: "ts" };
    });
    esbuild.onLoad({ filter: /[\\/]adapters[\\/]jellyfin\.ts$/ }, (args) => {
      const source = fs.readFileSync(args.path, "utf8");
      const contents = replaceOnce(
        source,
        /const imageUrl = \([\s\S]*?\n\};/,
        jellyfinCover,
        "jellyfin.imageUrl",
      );
      return { contents, loader: "ts" };
    });
  },
};

const resolvePlugin = {
  name: "streaming-shims",
  setup(esbuild) {
    esbuild.onResolve({ filter: /^@main\/services\/streaming\/snapshot$/ }, () => ({
      path: path.join(here, "src/snapshot.ts"),
    }));
    esbuild.onResolve({ filter: /.*/ }, (args) => {
      if (
        args.path === "./snapshot" &&
        /[\\/]services[\\/]streaming[\\/]/.test(args.importer ?? "")
      ) {
        return { path: path.join(here, "src/snapshot.ts") };
      }
      if (specific[args.path]) return { path: specific[args.path] };
      if (args.path.startsWith("@main/") || args.path.startsWith("@shared/")) {
        const resolved = resolveUpstream(args.path);
        if (resolved) return { path: resolved };
        return { errors: [{ text: `未找到上游模块: ${args.path}` }] };
      }
      if (args.path.startsWith("node:")) {
        const bare = args.path.slice("node:".length);
        if (specific[bare]) return { path: specific[bare] };
        return { errors: [{ text: `未提供 node 内建模块 shim: ${args.path}` }] };
      }
      return undefined;
    });
  },
};

const esbuild = loadEsbuild();
fs.mkdirSync(path.dirname(OUT), { recursive: true });

const result = await esbuild.build({
  entryPoints: [path.join(here, "src/streaming-entry.ts")],
  outfile: OUT,
  absWorkingDir: here,
  bundle: true,
  format: "esm",
  platform: "browser",
  target: "es2020",
  minify: true,
  lineLimit: 4000,
  charset: "utf8",
  legalComments: "none",
  treeShaking: true,
  metafile: true,
  inject: [path.join(here, "src/inject.ts")],
  define: {
    "process.env.NODE_ENV": '"production"',
    global: "globalThis",
  },
  tsconfig: path.join(here, "tsconfig.json"),
  plugins: [coverPlugin, resolvePlugin],
  logLevel: "info",
});

const output = fs.readFileSync(OUT, "utf8");
if (/\bfrom\s*["']\.\//.test(output) || /\bimport\s*\(\s*["']\.\//.test(output))
  throw new Error("单文件产物仍包含相对导入，请检查 splitting/external 配置");
if (output.includes("streaming-cover://"))
  throw new Error("产物仍包含 streaming-cover:// 伪 URL，封面替换未生效");

const stat = fs.statSync(OUT);
const lines = output.split(/\r?\n/).length;
console.log(`BUILD OK -> ${OUT}`);
console.log(`size: ${stat.size} bytes, lines: ${lines}`);
if (result.warnings.length) console.log(`warnings: ${result.warnings.length}`);
