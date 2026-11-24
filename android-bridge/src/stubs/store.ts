/** electron-store 桩：Android 端没有主进程设置存储，相关功能按默认关闭处理 */
export const store = {
  get: (_key: string, _def?: unknown) => _def ?? false,
  set: (_key: string, _value?: unknown) => undefined,
  has: (_key: string) => false,
  delete: (_key: string) => undefined,
  path: '',
  store: {},
  clear: () => undefined,
}
export default store