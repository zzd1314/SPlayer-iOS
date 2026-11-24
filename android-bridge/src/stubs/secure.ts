/**
 * Android 端安全存储 stub：替代 Electron safeStorage。
 * WebView 内无系统级密钥环，改用基于会话随机密钥的 base64 混淆存储，
 * 保证 addServer/removeServer 的密码加解密流程语义一致。
 */

let sessionKey = "";

/** 首次调用时生成会话级密钥（存储于 localStorage，重装后旧密文失效） */
const ensureKey = (): string => {
  if (sessionKey) return sessionKey;
  sessionKey = localStorage.getItem("splayer:sec-key") || "";
  if (!sessionKey) {
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    sessionKey = btoa(String.fromCharCode(...bytes));
    localStorage.setItem("splayer:sec-key", sessionKey);
  }
  return sessionKey;
};

const xorBytes = (input: Uint8Array): Uint8Array => {
  const key = ensureKey();
  const out = new Uint8Array(input.length);
  for (let i = 0; i < input.length; i++) {
    out[i] = input[i] ^ key.charCodeAt(i % key.length) & 0xff;
  }
  return out;
};

const bytesToText = (bytes: Uint8Array): string => {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return decodeURIComponent(escape(binary));
};

const textToBytes = (text: string): Uint8Array => {
  const binary = unescape(encodeURIComponent(text));
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
};

export const isSecureStorageAvailable = (): Promise<boolean> => Promise.resolve(true);

export const encryptSecret = (plainText: string): Promise<Uint8Array> => {
  const encrypted = xorBytes(textToBytes(plainText));
  let binary = "";
  for (const b of encrypted) binary += String.fromCharCode(b);
  return Promise.resolve(textToBytes(btoa(binary)));
};

export interface DecryptedSecret {
  plainText: string;
}

export const decryptSecret = async (buffer: Uint8Array): Promise<DecryptedSecret> => {
  let binary = "";
  for (const b of buffer) binary += String.fromCharCode(b);
  const obfuscated = Uint8Array.from(atob(binary), (c) => c.charCodeAt(0));
  return { plainText: bytesToText(xorBytes(obfuscated)) };
};