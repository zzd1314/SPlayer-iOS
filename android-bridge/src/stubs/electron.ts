/** Electron 桩：仅满足类型层面的导入，运行时不会触达桌面专属能力 */
export const app = { getPath: () => '', getVersion: () => '0.0.0' }
export const session = { defaultSession: {} }
export const BrowserWindow = class {}
export const ipcMain = { handle: () => undefined, on: () => undefined }

/** safeStorage 桩：config.ts 的密码加密经 secureStorage stub 间接实现，这里仅兜底 */
export const safeStorage = {
  isEncryptionAvailable: () => true,
  encryptString: (plain: string) => Buffer.from(plain, 'utf-8'),
  decryptString: (buffer: Uint8Array) => Buffer.from(buffer).toString('utf-8'),
}

/** net 桩：adapters 使用全局 fetch，此处仅兜底 net.fetch */
export const net = { fetch: (...args: unknown[]) => fetch(args[0] as RequestInfo, args[1] as RequestInit) }

/** protocol 桩：stream-cover:// 自定义协议在 WebView 内不可注册，封面走直链 */
export const protocol = {
  handle: () => true,
  registerFileProtocol: () => true,
  registerStreamProtocol: () => true,
}
export default {}