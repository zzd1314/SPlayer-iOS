// streaming-api.js 构建脚本：用 esbuild JS API 避免 shell 引号转义问题
// 相对路径一律基于本脚本所在目录解析，不受 cwd 影响
import * as esbuild from 'esbuild'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const outfile = process.argv[2] || path.join(here, 'streaming-api.js')

await esbuild.build({
  entryPoints: [path.join(here, 'src/streaming-entry.ts')],
  bundle: true,
  platform: 'browser',
  format: 'iife',
  outfile,
  absWorkingDir: here,
  inject: ['./src/shim.cjs'],
  define: {
    'process.env.NODE_ENV': '"production"',
    global: 'globalThis',
  },
  alias: {
    '@main': '../electron/main',
    '@main/database': './src/stubs/db.ts',
    '@main/database/streaming/albums': './src/stubs/db.ts',
    '@main/database/streaming/artists': './src/stubs/db.ts',
    '@main/database/streaming/playlists': './src/stubs/db.ts',
    '@main/database/streaming/tracks': './src/stubs/db.ts',
    '@main/utils/secureStorage': './src/stubs/secure.ts',
    '@main/utils/paths': './src/stubs/misc.ts',
    '@main/utils/broadcast': './src/stubs/misc.ts',
    '@main/utils/protocol': './src/stubs/misc.ts',
    '@main/services/streaming/coverProtocol': './src/stubs/misc.ts',
    '@main/utils/proxy': './src/stubs/proxy.ts',
    '@main/utils/logger': './src/stubs/logger.ts',
    '@main/store': './src/stubs/store.ts',
    electron: './src/stubs/electron.ts',
    atomically: './src/stubs/misc.ts',
    'node:crypto': 'crypto-browserify',
    'node:fs': './src/stubs/misc.ts',
    'node:os': './src/stubs/os.ts',
    'node:zlib': './src/stubs/zlib.ts',
    'node:path': 'path-browserify',
    stream: 'readable-stream',
    path: 'path-browserify',
  },
  tsconfig: path.join(here, 'tsconfig.json'),
  logLevel: 'info',
})
console.log('BUILD OK ->', outfile)