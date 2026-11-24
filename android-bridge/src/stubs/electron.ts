/** Electron 桩：仅满足类型层面的导入，运行时不会触达桌面专属能力 */
export const app = { getPath: () => '', getVersion: () => '0.0.0' }
export const session = { defaultSession: {} }
export const BrowserWindow = class {}
export const ipcMain = { handle: () => undefined, on: () => undefined }
export default {}