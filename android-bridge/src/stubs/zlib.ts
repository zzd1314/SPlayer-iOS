/** node:zlib 桩：ENCRYPT_RESPONSE 关闭时不会被调用 */
export const gunzipSync = () => { throw new Error('zlib unsupported in webview') }
export const gzipSync = () => { throw new Error('zlib unsupported in webview') }
export const zstdCompressSync = () => { throw new Error('zstd unsupported in webview') }
export default { gunzipSync, gzipSync, zstdCompressSync }