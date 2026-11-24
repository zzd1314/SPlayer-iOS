/** 会话存储桩：netease 会话由 entry.ts 直接写入 localStorage */
export const getSessionCookies = (_platform: string): Record<string, string> => ({})
export const saveSessionCookies = (_platform: string, _cookies: Record<string, string>) => undefined
export const clearSessionCookies = (_platform: string) => undefined