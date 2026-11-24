type Level = 'debug' | 'info' | 'warn' | 'error'
const make = (tag: string) => ({
  debug: (...a: unknown[]) => console.debug(tag, ...a),
  info: (...a: unknown[]) => console.info(tag, ...a),
  warn: (...a: unknown[]) => console.warn(tag, ...a),
  error: (...a: unknown[]) => console.error(tag, ...a),
})
export const coreLog = make('[core]')
export const neteaseLog = make('[netease]')
export const qqLog = make('[qq]')
export const kugouLog = make('[kugou]')
export const mainLog = make('[main]')
export default make('[log]')