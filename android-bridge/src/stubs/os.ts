/** node:os 桩：请求层仅用 type/release 拼 UA */
export const type = () => 'Linux'
export const release = () => '5.15.0-android'
export const arch = () => 'arm64'
export const platform = () => 'linux'
export const hostname = () => 'splayer-android'
export const userInfo = () => ({ username: 'android', homedir: '/data' })
export const tmpdir = () => '/tmp'
export default { type, release, arch, platform, hostname, tmpdir }