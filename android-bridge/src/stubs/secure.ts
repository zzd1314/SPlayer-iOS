/**
 * Android 端安全存储 stub：替代 Electron safeStorage。
 * WebView 没有系统密钥环，这里用 localStorage 中的随机密钥做 XOR 混淆后 base64 存储；
 * 只用于避免明文落盘，不提供系统级密钥保护。
 */
import { Buffer } from "./buffer";

const KEY_STORAGE = "splayer:sec-key";

let cachedKey: Uint8Array | null = null;

const randomBytes = (size: number): Uint8Array => {
  const bytes = new Uint8Array(size);
  const webCrypto = (globalThis as { crypto?: Crypto }).crypto;
  if (webCrypto?.getRandomValues) webCrypto.getRandomValues(bytes);
  else for (let i = 0; i < size; i++) bytes[i] = Math.floor(Math.random() * 256);
  return bytes;
};

const loadKey = (): Uint8Array => {
  if (cachedKey) return cachedKey;
  const storage = (globalThis as { localStorage?: Storage }).localStorage;
  const stored = storage?.getItem(KEY_STORAGE);
  if (stored) {
    try {
      cachedKey = Buffer.from(stored, "base64");
      return cachedKey;
    } catch {
      // 损坏时重新生成
    }
  }
  cachedKey = randomBytes(32);
  try {
    storage?.setItem(KEY_STORAGE, Buffer.from(cachedKey).toString("base64"));
  } catch {
    // 存储不可用时仅保留内存密钥
  }
  return cachedKey;
};

const xor = (input: Uint8Array): Uint8Array => {
  const key = loadKey();
  const out = new Uint8Array(input.length);
  for (let i = 0; i < input.length; i++) out[i] = input[i] ^ key[i % key.length];
  return out;
};

const utf8Encode = (text: string): Uint8Array => new TextEncoder().encode(text);
const utf8Decode = (bytes: Uint8Array): string => new TextDecoder("utf-8").decode(bytes);

export interface DecryptedSecret {
  plainText: string;
  needsReEncrypt: boolean;
}

export const isSecureStorageAvailable = (): Promise<boolean> => Promise.resolve(true);

/** 加密明文，返回 Buffer 以支持上游 `.toString("base64")` */
export const encryptSecret = (plainText: string): Promise<Buffer> => {
  return Promise.resolve(Buffer.from(xor(utf8Encode(plainText))));
};

/** 解密密文，固定返回不需要轮换密钥 */
export const decryptSecret = async (buffer: Uint8Array): Promise<DecryptedSecret> => {
  const bytes = buffer instanceof Uint8Array ? buffer : Buffer.from(buffer as ArrayBuffer);
  return { plainText: utf8Decode(xor(bytes)), needsReEncrypt: false };
};
